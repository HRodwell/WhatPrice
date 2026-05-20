import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show ConflictAlgorithm;
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'models.dart';
import 'services/image_storage.dart';

const _uuid = Uuid();
String _nowIso() => DateTime.now().toUtc().toIso8601String();

const _notDeleted = 'deleted_at IS NULL';

class AppState extends ChangeNotifier {
  AppState(this._db);
  final AppDatabase _db;
  AppDatabase get db => _db;

  List<Pantry> _pantries = [];
  List<Ingredient> _ingredients = [];
  List<Recipe> _recipes = [];
  AppSettings _settings = AppSettings.defaults;
  Map<int, String> _firstImageByRecipeId = {};
  Map<(int, int), RecipeCostSnapshot> _snapshots = {};
  Map<int, Map<int, IngredientPrice>> _pricesByPantry = {};
  Map<int, _ProductionAggregate> _productionByRecipe = {};

  List<Pantry> get pantries => _pantries;
  List<Ingredient> get ingredients => _ingredients;
  List<Recipe> get recipes => _recipes;
  AppSettings get settings => _settings;
  String? firstImageOf(int recipeId) => _firstImageByRecipeId[recipeId];

  Pantry get activePantry {
    if (_pantries.isEmpty) {
      return const Pantry(id: 1, name: 'Home');
    }
    return _pantries.firstWhere(
      (p) => p.id == _settings.activePantryId,
      orElse: () => _pantries.first,
    );
  }

  int get activePantryId => activePantry.id ?? 1;

  RecipeCostSnapshot? snapshotOf(int recipeId, {int? pantryId}) =>
      _snapshots[(recipeId, pantryId ?? activePantryId)];

  int productionSessionsOf(int recipeId) =>
      _productionByRecipe[recipeId]?.sessions ?? 0;
  int productionBatchesOf(int recipeId) =>
      _productionByRecipe[recipeId]?.batches ?? 0;
  DateTime? lastProductionAt(int recipeId) =>
      _productionByRecipe[recipeId]?.lastMadeAt;

  IngredientPrice? priceFor(int ingredientId, {int? pantryId}) =>
      _pricesByPantry[pantryId ?? activePantryId]?[ingredientId];

  Map<int, IngredientPrice> pricesForPantry(int pantryId) =>
      _pricesByPantry[pantryId] ?? const {};

  Map<int, Ingredient> get ingredientsById => {
        for (final i in _ingredients)
          if (i.id != null) i.id!: i,
      };

  Future<void> load() async {
    await Future.wait([
      _loadPantries(),
      _loadIngredients(),
      _loadRecipes(),
      _loadSettings(),
      _loadFirstImages(),
      _loadSnapshots(),
      _loadPrices(),
      _loadProductionAggregates(),
    ]);
    notifyListeners();
  }

  Future<void> reloadAll() => load();

  // ---- sync helpers ----

  Map<String, Object?> _stampInsert(Map<String, Object?> map) {
    final out = Map<String, Object?>.from(map);
    out['sync_id'] ??= _uuid.v4();
    out['updated_at'] = _nowIso();
    out['deleted_at'] = null;
    return out;
  }

  Map<String, Object?> _stampUpdate(Map<String, Object?> map) {
    final out = Map<String, Object?>.from(map);
    out['updated_at'] = _nowIso();
    return out;
  }

  Future<int> _softDelete(
    String table, {
    required String where,
    required List<Object?> whereArgs,
  }) async {
    return _db.raw.update(
      table,
      {'deleted_at': _nowIso(), 'updated_at': _nowIso()},
      where: '($where) AND $_notDeleted',
      whereArgs: whereArgs,
    );
  }

  // ---- pantries ----

  Future<void> _loadPantries() async {
    final rows = await _db.raw
        .query('pantries', where: _notDeleted, orderBy: 'id');
    _pantries = rows.map(Pantry.fromMap).toList();
  }

  Future<int> upsertPantry(Pantry pantry) async {
    final id = pantry.id == null
        ? await _db.raw.insert('pantries', _stampInsert(pantry.toMap()))
        : await _updateById('pantries', pantry.id!, _stampUpdate(pantry.toMap()));
    await _loadPantries();
    notifyListeners();
    return id;
  }

  Future<void> deletePantry(int id) async {
    if (_pantries.length <= 1) {
      throw StateError('Cannot delete the last pantry.');
    }
    await _softDelete('ingredient_prices',
        where: 'pantry_id = ?', whereArgs: [id]);
    await _softDelete('recipe_cost_snapshots',
        where: 'pantry_id = ?', whereArgs: [id]);
    await _softDelete('productions',
        where: 'pantry_id = ?', whereArgs: [id]);
    await _softDelete('pantries', where: 'id = ?', whereArgs: [id]);
    if (_settings.activePantryId == id) {
      await _loadPantries();
      final fallback = _pantries.first.id!;
      await saveSettings(_settings.copyWith(activePantryId: fallback));
    } else {
      await _loadPantries();
    }
    await Future.wait(
        [_loadPrices(), _loadSnapshots(), _loadProductionAggregates()]);
    notifyListeners();
  }

  Future<void> setActivePantry(int pantryId) async {
    if (pantryId == _settings.activePantryId) return;
    await saveSettings(_settings.copyWith(activePantryId: pantryId));
  }

  // ---- ingredients ----

  Future<void> _loadIngredients() async {
    final rows = await _db.raw.query(
      'ingredients',
      where: _notDeleted,
      orderBy: 'name COLLATE NOCASE',
    );
    _ingredients = rows.map(Ingredient.fromMap).toList();
  }

  Future<int> upsertIngredient(Ingredient i) async {
    final id = i.id == null
        ? await _db.raw.insert('ingredients', _stampInsert(i.toMap()))
        : await _updateById('ingredients', i.id!, _stampUpdate(i.toMap()));
    await _loadIngredients();
    notifyListeners();
    return id;
  }

  Future<void> deleteIngredient(int id) async {
    // Block if any non-deleted recipe still uses this ingredient.
    final used = await _db.raw.rawQuery(
      '''SELECT COUNT(*) AS c FROM recipe_ingredients
         WHERE ingredient_id = ? AND deleted_at IS NULL''',
      [id],
    );
    if ((used.first['c'] as num).toInt() > 0) {
      throw StateError('Ingredient is still used in a recipe.');
    }
    await _softDelete('ingredient_prices',
        where: 'ingredient_id = ?', whereArgs: [id]);
    await _softDelete('ingredients', where: 'id = ?', whereArgs: [id]);
    await Future.wait([_loadIngredients(), _loadPrices()]);
    notifyListeners();
  }

  // ---- ingredient prices ----

  Future<void> _loadPrices() async {
    final rows = await _db.raw.query('ingredient_prices', where: _notDeleted);
    final map = <int, Map<int, IngredientPrice>>{};
    for (final r in rows.map(IngredientPrice.fromMap)) {
      map.putIfAbsent(r.pantryId, () => {})[r.ingredientId] = r;
    }
    _pricesByPantry = map;
  }

  Future<void> upsertPrice(IngredientPrice price) async {
    final existing = await _db.raw.query(
      'ingredient_prices',
      columns: ['id', 'sync_id'],
      where: 'ingredient_id = ? AND pantry_id = ?',
      whereArgs: [price.ingredientId, price.pantryId],
    );
    final map = price.toMap();
    if (existing.isNotEmpty) {
      final existingId = (existing.first['id'] as num).toInt();
      await _db.raw.update(
        'ingredient_prices',
        _stampUpdate({...map, 'sync_id': existing.first['sync_id']}),
        where: 'id = ?',
        whereArgs: [existingId],
      );
    } else {
      await _db.raw.insert('ingredient_prices', _stampInsert(map));
    }
    await _loadPrices();
    notifyListeners();
  }

  Future<void> deletePrice(int ingredientId, int pantryId) async {
    await _softDelete(
      'ingredient_prices',
      where: 'ingredient_id = ? AND pantry_id = ?',
      whereArgs: [ingredientId, pantryId],
    );
    await _loadPrices();
    notifyListeners();
  }

  // ---- recipes ----

  Future<void> _loadRecipes() async {
    final rows = await _db.raw.query(
      'recipes',
      where: _notDeleted,
      orderBy: 'name COLLATE NOCASE',
    );
    _recipes = rows.map(Recipe.fromMap).toList();
  }

  Future<int> upsertRecipe(Recipe r) async {
    final id = r.id == null
        ? await _db.raw.insert('recipes', _stampInsert(r.toMap()))
        : await _updateById('recipes', r.id!, _stampUpdate(r.toMap()));
    await _loadRecipes();
    notifyListeners();
    return id;
  }

  Future<void> deleteRecipe(int id) async {
    final imgRows = await _db.raw.query(
      'recipe_images',
      columns: ['path'],
      where: 'recipe_id = ? AND $_notDeleted',
      whereArgs: [id],
    );
    await _softDelete('recipe_images',
        where: 'recipe_id = ?', whereArgs: [id]);
    await _softDelete('recipe_ingredients',
        where: 'recipe_id = ?', whereArgs: [id]);
    await _softDelete('recipe_cost_snapshots',
        where: 'recipe_id = ?', whereArgs: [id]);
    await _softDelete('productions',
        where: 'recipe_id = ?', whereArgs: [id]);
    await _softDelete('recipes', where: 'id = ?', whereArgs: [id]);
    for (final r in imgRows) {
      await ImageStorage.instance.delete(r['path'] as String);
    }
    await Future.wait([
      _loadRecipes(),
      _loadFirstImages(),
      _loadSnapshots(),
      _loadProductionAggregates(),
    ]);
    notifyListeners();
  }

  // ---- recipe ingredients ----

  Future<List<RecipeIngredient>> loadRecipeLines(int recipeId) async {
    final rows = await _db.raw.query(
      'recipe_ingredients',
      where: 'recipe_id = ? AND $_notDeleted',
      whereArgs: [recipeId],
    );
    return rows.map(RecipeIngredient.fromMap).toList();
  }

  Future<void> replaceRecipeLines(
      int recipeId, List<RecipeIngredient> lines) async {
    final existing = await _db.raw.query(
      'recipe_ingredients',
      where: 'recipe_id = ? AND $_notDeleted',
      whereArgs: [recipeId],
    );
    final existingByKey = <(int, double), Map<String, Object?>>{};
    for (final row in existing) {
      final key = (
        (row['ingredient_id'] as num).toInt(),
        (row['quantity'] as num).toDouble(),
      );
      existingByKey[key] = row;
    }
    final keepIds = <int>{};
    for (final l in lines) {
      final key = (l.ingredientId, l.quantity);
      final match = existingByKey[key];
      if (match != null) {
        keepIds.add((match['id'] as num).toInt());
        continue;
      }
      await _db.raw.insert(
        'recipe_ingredients',
        _stampInsert({
          'recipe_id': recipeId,
          'ingredient_id': l.ingredientId,
          'quantity': l.quantity,
        }),
      );
    }
    for (final row in existing) {
      final rowId = (row['id'] as num).toInt();
      if (keepIds.contains(rowId)) continue;
      await _softDelete('recipe_ingredients',
          where: 'id = ?', whereArgs: [rowId]);
    }
  }

  // ---- recipe images ----

  Future<void> _loadFirstImages() async {
    final rows = await _db.raw.rawQuery(
      '''SELECT recipe_id, path FROM recipe_images
         WHERE deleted_at IS NULL
         ORDER BY recipe_id, sort_order, id''',
    );
    final map = <int, String>{};
    for (final r in rows) {
      final rid = (r['recipe_id'] as num).toInt();
      map.putIfAbsent(rid, () => r['path'] as String);
    }
    _firstImageByRecipeId = map;
  }

  Future<List<RecipeImage>> loadRecipeImages(int recipeId) async {
    final rows = await _db.raw.query(
      'recipe_images',
      where: 'recipe_id = ? AND $_notDeleted',
      whereArgs: [recipeId],
      orderBy: 'sort_order, id',
    );
    return rows.map(RecipeImage.fromMap).toList();
  }

  Future<void> addRecipeImages(int recipeId, List<String> paths) async {
    if (paths.isEmpty) return;
    final existing = await _db.raw.rawQuery(
      '''SELECT COALESCE(MAX(sort_order), -1) + 1 AS next FROM recipe_images
         WHERE recipe_id = ? AND deleted_at IS NULL''',
      [recipeId],
    );
    var next = (existing.first['next'] as num).toInt();
    for (final path in paths) {
      await _db.raw.insert(
        'recipe_images',
        _stampInsert({
          'recipe_id': recipeId,
          'path': path,
          'sort_order': next++,
        }),
      );
    }
    await _loadFirstImages();
    notifyListeners();
  }

  Future<void> removeRecipeImage(RecipeImage image) async {
    if (image.id == null) return;
    await _softDelete('recipe_images',
        where: 'id = ?', whereArgs: [image.id]);
    await ImageStorage.instance.delete(image.path);
    await _loadFirstImages();
    notifyListeners();
  }

  // ---- recipe cost snapshots ----

  Future<void> _loadSnapshots() async {
    final rows = await _db.raw.query(
      'recipe_cost_snapshots',
      where: _notDeleted,
    );
    _snapshots = {
      for (final r in rows.map(RecipeCostSnapshot.fromMap))
        (r.recipeId, r.pantryId): r,
    };
  }

  Future<void> saveSnapshot(RecipeCostSnapshot snap) async {
    final map = snap.toMap();
    final existing = await _db.raw.query(
      'recipe_cost_snapshots',
      columns: ['sync_id'],
      where: 'recipe_id = ? AND pantry_id = ?',
      whereArgs: [snap.recipeId, snap.pantryId],
    );
    if (existing.isNotEmpty) {
      map['sync_id'] = existing.first['sync_id'];
    }
    await _db.raw.insert(
      'recipe_cost_snapshots',
      _stampInsert(map),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _snapshots = {
      ..._snapshots,
      (snap.recipeId, snap.pantryId): snap,
    };
    notifyListeners();
  }

  // ---- productions ----

  Future<void> _loadProductionAggregates() async {
    final rows = await _db.raw.rawQuery('''
      SELECT recipe_id,
             COUNT(*) AS sessions,
             SUM(batches) AS total_batches,
             MAX(made_at) AS last_made
        FROM productions
       WHERE deleted_at IS NULL
       GROUP BY recipe_id
    ''');
    final map = <int, _ProductionAggregate>{};
    for (final r in rows) {
      final id = (r['recipe_id'] as num).toInt();
      map[id] = _ProductionAggregate(
        sessions: (r['sessions'] as num).toInt(),
        batches: ((r['total_batches'] ?? 0) as num).toInt(),
        lastMadeAt:
            r['last_made'] == null ? null : DateTime.parse(r['last_made'] as String),
      );
    }
    _productionByRecipe = map;
  }

  Future<List<ProductionRecord>> loadProductions(int recipeId) async {
    final rows = await _db.raw.query(
      'productions',
      where: 'recipe_id = ? AND $_notDeleted',
      whereArgs: [recipeId],
      orderBy: 'made_at DESC',
    );
    return rows.map(ProductionRecord.fromMap).toList();
  }

  Future<int> upsertProduction(ProductionRecord p) async {
    final id = p.id == null
        ? await _db.raw.insert('productions', _stampInsert(p.toMap()))
        : await _updateById('productions', p.id!, _stampUpdate(p.toMap()));
    await _loadProductionAggregates();
    notifyListeners();
    return id;
  }

  Future<void> deleteProduction(int id) async {
    await _softDelete('productions', where: 'id = ?', whereArgs: [id]);
    await _loadProductionAggregates();
    notifyListeners();
  }

  // ---- settings ----

  Future<void> _loadSettings() async {
    final rows = await _db.raw.query('settings', where: 'id = 1');
    _settings = rows.isEmpty
        ? AppSettings.defaults
        : AppSettings.fromMap(rows.first);
  }

  Future<void> saveSettings(AppSettings s) async {
    await _db.raw.update('settings', s.toMap(), where: 'id = 1');
    _settings = s;
    notifyListeners();
  }

  // ---- local state KV ----

  Future<String?> getLocalState(String key) async {
    final rows = await _db.raw
        .query('local_state', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setLocalState(String key, String? value) async {
    if (value == null) {
      await _db.raw.delete('local_state', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.raw.insert(
        'local_state',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<int> _updateById(String table, int id, Map<String, Object?> map) async {
    await _db.raw.update(table, map, where: 'id = ?', whereArgs: [id]);
    return id;
  }
}

class _ProductionAggregate {
  final int sessions;
  final int batches;
  final DateTime? lastMadeAt;
  const _ProductionAggregate({
    required this.sessions,
    required this.batches,
    required this.lastMadeAt,
  });
}
