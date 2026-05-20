import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();

class AppDatabase {
  AppDatabase._(this._db);
  final Database _db;
  Database get raw => _db;

  static AppDatabase? _instance;

  static Future<AppDatabase> open() async {
    if (_instance != null) return _instance!;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'whatprice.db');
    final db = await openDatabase(
      path,
      version: 7,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON;'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _instance = AppDatabase._(db);
    return _instance!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    const syncCols =
        'sync_id TEXT NOT NULL UNIQUE, updated_at TEXT NOT NULL, deleted_at TEXT';
    await db.execute('''
      CREATE TABLE pantries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        $syncCols
      );
    ''');
    final nowIso = _nowIso();
    await db.insert('pantries', {
      'id': 1,
      'name': 'Home',
      'sync_id': _generateSyncId(),
      'updated_at': nowIso,
    });

    await db.execute('''
      CREATE TABLE ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        allergen_flags INTEGER NOT NULL DEFAULT 0,
        $syncCols
      );
    ''');
    await db.execute('''
      CREATE TABLE ingredient_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
        pantry_id INTEGER NOT NULL REFERENCES pantries(id) ON DELETE CASCADE,
        pack_size REAL NOT NULL,
        pack_cost REAL NOT NULL,
        $syncCols,
        UNIQUE(ingredient_id, pantry_id)
      );
    ''');
    await db.execute(
      'CREATE INDEX idx_ingredient_prices_pantry ON ingredient_prices(pantry_id);',
    );
    await db.execute('''
      CREATE TABLE recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        yield_pieces INTEGER NOT NULL,
        oven_minutes REAL NOT NULL,
        labour_minutes REAL NOT NULL,
        notes TEXT,
        $syncCols
      );
    ''');
    await db.execute('''
      CREATE TABLE recipe_ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE RESTRICT,
        quantity REAL NOT NULL,
        $syncCols
      );
    ''');
    await db.execute('''
      CREATE TABLE settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        electricity_rate REAL NOT NULL,
        oven_kw REAL NOT NULL,
        hourly_wage REAL NOT NULL,
        margin_percent REAL NOT NULL,
        include_labour INTEGER NOT NULL,
        currency_symbol TEXT NOT NULL,
        active_pantry_id INTEGER NOT NULL DEFAULT 1
      );
    ''');
    await db.insert('settings', AppSettings.defaults.toMap());
    await _createRecipeImages(db);
    await _createRecipeCostSnapshots(db);
    await _createProductions(db);
    await _createLocalState(db);
  }

  static Future<void> _onUpgrade(Database db, int from, int to) async {
    if (from < 2) {
      await _createRecipeImages(db);
    }
    if (from < 3) {
      await db.execute(
        'ALTER TABLE ingredients ADD COLUMN allergen_flags INTEGER NOT NULL DEFAULT 0;',
      );
    }
    if (from < 4) {
      await _createRecipeCostSnapshotsLegacy(db);
    }
    if (from < 5) {
      await _migrateToV5(db);
    }
    if (from < 6) {
      await _createProductions(db);
    }
    if (from < 7) {
      await _migrateToV7(db);
    }
  }

  static Future<void> _migrateToV7(Database db) async {
    const syncTables = [
      'pantries',
      'ingredients',
      'ingredient_prices',
      'recipes',
      'recipe_ingredients',
      'recipe_images',
      'recipe_cost_snapshots',
      'productions',
    ];
    for (final table in syncTables) {
      await db.execute('ALTER TABLE $table ADD COLUMN sync_id TEXT;');
      await db.execute('ALTER TABLE $table ADD COLUMN updated_at TEXT;');
      await db.execute('ALTER TABLE $table ADD COLUMN deleted_at TEXT;');
      final rows = await db.query(table, columns: ['rowid']);
      final now = _nowIso();
      for (final row in rows) {
        await db.update(
          table,
          {
            'sync_id': _generateSyncId(),
            'updated_at': now,
          },
          where: 'rowid = ?',
          whereArgs: [row['rowid']],
        );
      }
      await db.execute(
        'CREATE UNIQUE INDEX idx_${table}_sync_id ON $table(sync_id);',
      );
    }
    await _createLocalState(db);
  }

  static Future<void> _createLocalState(Database db) async {
    await db.execute('''
      CREATE TABLE local_state (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
  }

  static Future<void> _migrateToV5(Database db) async {
    // sqflite wraps onUpgrade in a transaction; PRAGMA foreign_keys = OFF is
    // silently ignored inside a transaction. defer_foreign_keys delays FK
    // enforcement until COMMIT, which is what we need for the table rebuild.
    await db.execute('PRAGMA defer_foreign_keys = ON;');

    await db.execute('''
      CREATE TABLE pantries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      );
    ''');
    await db.insert('pantries', {'id': 1, 'name': 'Home'});

    await db.execute('''
      CREATE TABLE ingredient_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
        pantry_id INTEGER NOT NULL REFERENCES pantries(id) ON DELETE CASCADE,
        pack_size REAL NOT NULL,
        pack_cost REAL NOT NULL,
        UNIQUE(ingredient_id, pantry_id)
      );
    ''');
    await db.execute(
      'CREATE INDEX idx_ingredient_prices_pantry ON ingredient_prices(pantry_id);',
    );
    await db.execute('''
      INSERT INTO ingredient_prices (ingredient_id, pantry_id, pack_size, pack_cost)
      SELECT id, 1, pack_size, pack_cost FROM ingredients;
    ''');

    await db.execute('''
      CREATE TABLE ingredients_new (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        allergen_flags INTEGER NOT NULL DEFAULT 0
      );
    ''');
    await db.execute('''
      INSERT INTO ingredients_new (id, name, unit, allergen_flags)
      SELECT id, name, unit, allergen_flags FROM ingredients;
    ''');
    await db.execute('DROP TABLE ingredients;');
    await db.execute('ALTER TABLE ingredients_new RENAME TO ingredients;');

    await db.execute('''
      CREATE TABLE recipe_cost_snapshots_new (
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        pantry_id INTEGER NOT NULL REFERENCES pantries(id) ON DELETE CASCADE,
        margin_percent REAL NOT NULL,
        include_labour INTEGER NOT NULL,
        ingredients_cost REAL NOT NULL,
        energy_cost REAL NOT NULL,
        labour_cost REAL NOT NULL,
        cost_per_piece REAL NOT NULL,
        suggested_price_per_piece REAL NOT NULL,
        suggested_batch_price REAL NOT NULL,
        computed_at TEXT NOT NULL,
        PRIMARY KEY(recipe_id, pantry_id)
      );
    ''');
    await db.execute('''
      INSERT INTO recipe_cost_snapshots_new (
        recipe_id, pantry_id, margin_percent, include_labour,
        ingredients_cost, energy_cost, labour_cost,
        cost_per_piece, suggested_price_per_piece, suggested_batch_price,
        computed_at
      )
      SELECT recipe_id, 1, margin_percent, include_labour,
             ingredients_cost, energy_cost, labour_cost,
             cost_per_piece, suggested_price_per_piece, suggested_batch_price,
             computed_at
      FROM recipe_cost_snapshots;
    ''');
    await db.execute('DROP TABLE recipe_cost_snapshots;');
    await db.execute(
      'ALTER TABLE recipe_cost_snapshots_new RENAME TO recipe_cost_snapshots;',
    );

    await db.execute(
      'ALTER TABLE settings ADD COLUMN active_pantry_id INTEGER NOT NULL DEFAULT 1;',
    );
  }

  static Future<void> _createRecipeImages(Database db) async {
    await db.execute('''
      CREATE TABLE recipe_images (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        path TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        sync_id TEXT NOT NULL UNIQUE,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      );
    ''');
    await db.execute(
      'CREATE INDEX idx_recipe_images_recipe_id ON recipe_images(recipe_id);',
    );
  }

  // v5 creates the pantry-aware snapshot table directly. This legacy creator
  // is only used during stepwise upgrades from v3 → v4.
  static Future<void> _createRecipeCostSnapshotsLegacy(Database db) async {
    await db.execute('''
      CREATE TABLE recipe_cost_snapshots (
        recipe_id INTEGER PRIMARY KEY REFERENCES recipes(id) ON DELETE CASCADE,
        margin_percent REAL NOT NULL,
        include_labour INTEGER NOT NULL,
        ingredients_cost REAL NOT NULL,
        energy_cost REAL NOT NULL,
        labour_cost REAL NOT NULL,
        cost_per_piece REAL NOT NULL,
        suggested_price_per_piece REAL NOT NULL,
        suggested_batch_price REAL NOT NULL,
        computed_at TEXT NOT NULL
      );
    ''');
  }

  static Future<void> _createProductions(Database db) async {
    await db.execute('''
      CREATE TABLE productions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        pantry_id INTEGER NOT NULL REFERENCES pantries(id) ON DELETE CASCADE,
        made_at TEXT NOT NULL,
        batches INTEGER NOT NULL,
        cost_per_piece REAL,
        notes TEXT,
        sync_id TEXT NOT NULL UNIQUE,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      );
    ''');
    await db.execute(
      'CREATE INDEX idx_productions_recipe ON productions(recipe_id, made_at);',
    );
  }

  static Future<void> _createRecipeCostSnapshots(Database db) async {
    await db.execute('''
      CREATE TABLE recipe_cost_snapshots (
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        pantry_id INTEGER NOT NULL REFERENCES pantries(id) ON DELETE CASCADE,
        margin_percent REAL NOT NULL,
        include_labour INTEGER NOT NULL,
        ingredients_cost REAL NOT NULL,
        energy_cost REAL NOT NULL,
        labour_cost REAL NOT NULL,
        cost_per_piece REAL NOT NULL,
        suggested_price_per_piece REAL NOT NULL,
        suggested_batch_price REAL NOT NULL,
        computed_at TEXT NOT NULL,
        sync_id TEXT NOT NULL UNIQUE,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        PRIMARY KEY(recipe_id, pantry_id)
      );
    ''');
  }
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

String _generateSyncId() => _uuid.v4();
