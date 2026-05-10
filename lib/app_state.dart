import 'package:flutter/foundation.dart';

import 'database.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  AppState(this._db);
  final AppDatabase _db;

  List<Ingredient> _ingredients = [];
  List<Recipe> _recipes = [];
  AppSettings _settings = AppSettings.defaults;

  List<Ingredient> get ingredients => _ingredients;
  List<Recipe> get recipes => _recipes;
  AppSettings get settings => _settings;

  Map<int, Ingredient> get ingredientsById => {
        for (final i in _ingredients)
          if (i.id != null) i.id!: i,
      };

  Future<void> load() async {
    await Future.wait([
      _loadIngredients(),
      _loadRecipes(),
      _loadSettings(),
    ]);
    notifyListeners();
  }

  Future<void> _loadIngredients() async {
    final rows = await _db.raw.query('ingredients', orderBy: 'name COLLATE NOCASE');
    _ingredients = rows.map(Ingredient.fromMap).toList();
  }

  Future<void> _loadRecipes() async {
    final rows = await _db.raw.query('recipes', orderBy: 'name COLLATE NOCASE');
    _recipes = rows.map(Recipe.fromMap).toList();
  }

  Future<void> _loadSettings() async {
    final rows = await _db.raw.query('settings', where: 'id = 1');
    _settings = rows.isEmpty
        ? AppSettings.defaults
        : AppSettings.fromMap(rows.first);
  }

  Future<int> upsertIngredient(Ingredient i) async {
    final id = i.id == null
        ? await _db.raw.insert('ingredients', i.toMap())
        : await _updateById('ingredients', i.id!, i.toMap());
    await _loadIngredients();
    notifyListeners();
    return id;
  }

  Future<void> deleteIngredient(int id) async {
    await _db.raw.delete('ingredients', where: 'id = ?', whereArgs: [id]);
    await _loadIngredients();
    notifyListeners();
  }

  Future<int> upsertRecipe(Recipe r) async {
    final id = r.id == null
        ? await _db.raw.insert('recipes', r.toMap())
        : await _updateById('recipes', r.id!, r.toMap());
    await _loadRecipes();
    notifyListeners();
    return id;
  }

  Future<void> deleteRecipe(int id) async {
    await _db.raw.delete('recipes', where: 'id = ?', whereArgs: [id]);
    await _loadRecipes();
    notifyListeners();
  }

  Future<List<RecipeIngredient>> loadRecipeLines(int recipeId) async {
    final rows = await _db.raw.query('recipe_ingredients',
        where: 'recipe_id = ?', whereArgs: [recipeId]);
    return rows.map(RecipeIngredient.fromMap).toList();
  }

  Future<void> replaceRecipeLines(
      int recipeId, List<RecipeIngredient> lines) async {
    final batch = _db.raw.batch();
    batch.delete('recipe_ingredients',
        where: 'recipe_id = ?', whereArgs: [recipeId]);
    for (final l in lines) {
      batch.insert(
        'recipe_ingredients',
        l.toMap()..['recipe_id'] = recipeId,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveSettings(AppSettings s) async {
    await _db.raw.update('settings', s.toMap(), where: 'id = 1');
    _settings = s;
    notifyListeners();
  }

  Future<int> _updateById(String table, int id, Map<String, Object?> map) async {
    await _db.raw.update(table, map, where: 'id = ?', whereArgs: [id]);
    return id;
  }
}
