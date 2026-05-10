import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'models.dart';

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
      version: 1,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON;'),
      onCreate: _onCreate,
    );
    _instance = AppDatabase._(db);
    return _instance!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        unit TEXT NOT NULL,
        pack_size REAL NOT NULL,
        pack_cost REAL NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        yield_pieces INTEGER NOT NULL,
        oven_minutes REAL NOT NULL,
        labour_minutes REAL NOT NULL,
        notes TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE recipe_ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
        ingredient_id INTEGER NOT NULL REFERENCES ingredients(id) ON DELETE RESTRICT,
        quantity REAL NOT NULL
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
        currency_symbol TEXT NOT NULL
      );
    ''');
    await db.insert('settings', AppSettings.defaults.toMap());
  }
}
