import 'allergens.dart';

enum Unit { gram, milliliter, each }

extension UnitX on Unit {
  String get short => switch (this) {
        Unit.gram => 'g',
        Unit.milliliter => 'ml',
        Unit.each => 'ea',
      };

  String get label => switch (this) {
        Unit.gram => 'Grams',
        Unit.milliliter => 'Millilitres',
        Unit.each => 'Each',
      };

  static Unit parse(String s) =>
      Unit.values.firstWhere((u) => u.name == s, orElse: () => Unit.gram);
}

class Pantry {
  final int? id;
  final String name;

  const Pantry({this.id, required this.name});

  Pantry copyWith({int? id, String? name}) =>
      Pantry(id: id ?? this.id, name: name ?? this.name);

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
      };

  factory Pantry.fromMap(Map<String, Object?> m) =>
      Pantry(id: m['id'] as int?, name: m['name'] as String);
}

class Ingredient {
  final int? id;
  final String name;
  final Unit unit;
  final AllergenSet allergens;

  const Ingredient({
    this.id,
    required this.name,
    required this.unit,
    this.allergens = AllergenSet.empty,
  });

  Ingredient copyWith({
    int? id,
    String? name,
    Unit? unit,
    AllergenSet? allergens,
  }) =>
      Ingredient(
        id: id ?? this.id,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        allergens: allergens ?? this.allergens,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'unit': unit.name,
        'allergen_flags': allergens.mask,
      };

  factory Ingredient.fromMap(Map<String, Object?> m) => Ingredient(
        id: m['id'] as int?,
        name: m['name'] as String,
        unit: UnitX.parse(m['unit'] as String),
        allergens: AllergenSet(((m['allergen_flags'] ?? 0) as num).toInt()),
      );
}

class IngredientPrice {
  final int? id;
  final int ingredientId;
  final int pantryId;
  final double packSize;
  final double packCost;

  const IngredientPrice({
    this.id,
    required this.ingredientId,
    required this.pantryId,
    required this.packSize,
    required this.packCost,
  });

  double get unitCost => packSize == 0 ? 0 : packCost / packSize;

  IngredientPrice copyWith({
    int? id,
    int? ingredientId,
    int? pantryId,
    double? packSize,
    double? packCost,
  }) =>
      IngredientPrice(
        id: id ?? this.id,
        ingredientId: ingredientId ?? this.ingredientId,
        pantryId: pantryId ?? this.pantryId,
        packSize: packSize ?? this.packSize,
        packCost: packCost ?? this.packCost,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'ingredient_id': ingredientId,
        'pantry_id': pantryId,
        'pack_size': packSize,
        'pack_cost': packCost,
      };

  factory IngredientPrice.fromMap(Map<String, Object?> m) => IngredientPrice(
        id: m['id'] as int?,
        ingredientId: (m['ingredient_id'] as num).toInt(),
        pantryId: (m['pantry_id'] as num).toInt(),
        packSize: (m['pack_size'] as num).toDouble(),
        packCost: (m['pack_cost'] as num).toDouble(),
      );
}

class Recipe {
  final int? id;
  final String name;
  final int yieldPieces;
  final double ovenMinutes;
  final double labourMinutes;
  final String? notes;

  const Recipe({
    this.id,
    required this.name,
    required this.yieldPieces,
    required this.ovenMinutes,
    required this.labourMinutes,
    this.notes,
  });

  Recipe copyWith({
    int? id,
    String? name,
    int? yieldPieces,
    double? ovenMinutes,
    double? labourMinutes,
    String? notes,
  }) =>
      Recipe(
        id: id ?? this.id,
        name: name ?? this.name,
        yieldPieces: yieldPieces ?? this.yieldPieces,
        ovenMinutes: ovenMinutes ?? this.ovenMinutes,
        labourMinutes: labourMinutes ?? this.labourMinutes,
        notes: notes ?? this.notes,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'yield_pieces': yieldPieces,
        'oven_minutes': ovenMinutes,
        'labour_minutes': labourMinutes,
        'notes': notes,
      };

  factory Recipe.fromMap(Map<String, Object?> m) => Recipe(
        id: m['id'] as int?,
        name: m['name'] as String,
        yieldPieces: (m['yield_pieces'] as num).toInt(),
        ovenMinutes: (m['oven_minutes'] as num).toDouble(),
        labourMinutes: (m['labour_minutes'] as num).toDouble(),
        notes: m['notes'] as String?,
      );
}

class RecipeImage {
  final int? id;
  final int recipeId;
  final String path;
  final int sortOrder;

  const RecipeImage({
    this.id,
    required this.recipeId,
    required this.path,
    required this.sortOrder,
  });

  RecipeImage copyWith({int? id, int? recipeId, String? path, int? sortOrder}) =>
      RecipeImage(
        id: id ?? this.id,
        recipeId: recipeId ?? this.recipeId,
        path: path ?? this.path,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'recipe_id': recipeId,
        'path': path,
        'sort_order': sortOrder,
      };

  factory RecipeImage.fromMap(Map<String, Object?> m) => RecipeImage(
        id: m['id'] as int?,
        recipeId: (m['recipe_id'] as num).toInt(),
        path: m['path'] as String,
        sortOrder: (m['sort_order'] as num).toInt(),
      );
}

class RecipeIngredient {
  final int? id;
  final int recipeId;
  final int ingredientId;
  final double quantity;

  const RecipeIngredient({
    this.id,
    required this.recipeId,
    required this.ingredientId,
    required this.quantity,
  });

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'recipe_id': recipeId,
        'ingredient_id': ingredientId,
        'quantity': quantity,
      };

  factory RecipeIngredient.fromMap(Map<String, Object?> m) => RecipeIngredient(
        id: m['id'] as int?,
        recipeId: (m['recipe_id'] as num).toInt(),
        ingredientId: (m['ingredient_id'] as num).toInt(),
        quantity: (m['quantity'] as num).toDouble(),
      );
}

class ProductionRecord {
  final int? id;
  final int recipeId;
  final int pantryId;
  final DateTime madeAt;
  final int batches;
  final double? costPerPiece;
  final String? notes;

  const ProductionRecord({
    this.id,
    required this.recipeId,
    required this.pantryId,
    required this.madeAt,
    required this.batches,
    this.costPerPiece,
    this.notes,
  });

  ProductionRecord copyWith({
    int? id,
    int? recipeId,
    int? pantryId,
    DateTime? madeAt,
    int? batches,
    double? costPerPiece,
    String? notes,
  }) =>
      ProductionRecord(
        id: id ?? this.id,
        recipeId: recipeId ?? this.recipeId,
        pantryId: pantryId ?? this.pantryId,
        madeAt: madeAt ?? this.madeAt,
        batches: batches ?? this.batches,
        costPerPiece: costPerPiece ?? this.costPerPiece,
        notes: notes ?? this.notes,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'recipe_id': recipeId,
        'pantry_id': pantryId,
        'made_at': madeAt.toIso8601String(),
        'batches': batches,
        'cost_per_piece': costPerPiece,
        'notes': notes,
      };

  factory ProductionRecord.fromMap(Map<String, Object?> m) => ProductionRecord(
        id: m['id'] as int?,
        recipeId: (m['recipe_id'] as num).toInt(),
        pantryId: (m['pantry_id'] as num).toInt(),
        madeAt: DateTime.parse(m['made_at'] as String),
        batches: (m['batches'] as num).toInt(),
        costPerPiece: (m['cost_per_piece'] as num?)?.toDouble(),
        notes: m['notes'] as String?,
      );
}

class RecipeCostSnapshot {
  final int recipeId;
  final int pantryId;
  final double marginPercent;
  final bool includeLabour;
  final double ingredientsCost;
  final double energyCost;
  final double labourCost;
  final double costPerPiece;
  final double suggestedPricePerPiece;
  final double suggestedBatchPrice;
  final DateTime computedAt;

  const RecipeCostSnapshot({
    required this.recipeId,
    required this.pantryId,
    required this.marginPercent,
    required this.includeLabour,
    required this.ingredientsCost,
    required this.energyCost,
    required this.labourCost,
    required this.costPerPiece,
    required this.suggestedPricePerPiece,
    required this.suggestedBatchPrice,
    required this.computedAt,
  });

  double get totalCost => ingredientsCost + energyCost + labourCost;

  Map<String, Object?> toMap() => {
        'recipe_id': recipeId,
        'pantry_id': pantryId,
        'margin_percent': marginPercent,
        'include_labour': includeLabour ? 1 : 0,
        'ingredients_cost': ingredientsCost,
        'energy_cost': energyCost,
        'labour_cost': labourCost,
        'cost_per_piece': costPerPiece,
        'suggested_price_per_piece': suggestedPricePerPiece,
        'suggested_batch_price': suggestedBatchPrice,
        'computed_at': computedAt.toIso8601String(),
      };

  factory RecipeCostSnapshot.fromMap(Map<String, Object?> m) =>
      RecipeCostSnapshot(
        recipeId: (m['recipe_id'] as num).toInt(),
        pantryId: (m['pantry_id'] as num).toInt(),
        marginPercent: (m['margin_percent'] as num).toDouble(),
        includeLabour: (m['include_labour'] as int) == 1,
        ingredientsCost: (m['ingredients_cost'] as num).toDouble(),
        energyCost: (m['energy_cost'] as num).toDouble(),
        labourCost: (m['labour_cost'] as num).toDouble(),
        costPerPiece: (m['cost_per_piece'] as num).toDouble(),
        suggestedPricePerPiece:
            (m['suggested_price_per_piece'] as num).toDouble(),
        suggestedBatchPrice: (m['suggested_batch_price'] as num).toDouble(),
        computedAt: DateTime.parse(m['computed_at'] as String),
      );
}

class AppSettings {
  final double electricityRatePerKwh;
  final double ovenKw;
  final double hourlyWage;
  final double marginPercent;
  final bool includeLabour;
  final String currencySymbol;
  final int activePantryId;

  const AppSettings({
    required this.electricityRatePerKwh,
    required this.ovenKw,
    required this.hourlyWage,
    required this.marginPercent,
    required this.includeLabour,
    required this.currencySymbol,
    required this.activePantryId,
  });

  static const defaults = AppSettings(
    electricityRatePerKwh: 0.30,
    ovenKw: 2.5,
    hourlyWage: 20.0,
    marginPercent: 60.0,
    includeLabour: true,
    currencySymbol: '\$',
    activePantryId: 1,
  );

  AppSettings copyWith({
    double? electricityRatePerKwh,
    double? ovenKw,
    double? hourlyWage,
    double? marginPercent,
    bool? includeLabour,
    String? currencySymbol,
    int? activePantryId,
  }) =>
      AppSettings(
        electricityRatePerKwh:
            electricityRatePerKwh ?? this.electricityRatePerKwh,
        ovenKw: ovenKw ?? this.ovenKw,
        hourlyWage: hourlyWage ?? this.hourlyWage,
        marginPercent: marginPercent ?? this.marginPercent,
        includeLabour: includeLabour ?? this.includeLabour,
        currencySymbol: currencySymbol ?? this.currencySymbol,
        activePantryId: activePantryId ?? this.activePantryId,
      );

  Map<String, Object?> toMap() => {
        'id': 1,
        'electricity_rate': electricityRatePerKwh,
        'oven_kw': ovenKw,
        'hourly_wage': hourlyWage,
        'margin_percent': marginPercent,
        'include_labour': includeLabour ? 1 : 0,
        'currency_symbol': currencySymbol,
        'active_pantry_id': activePantryId,
      };

  factory AppSettings.fromMap(Map<String, Object?> m) => AppSettings(
        electricityRatePerKwh: (m['electricity_rate'] as num).toDouble(),
        ovenKw: (m['oven_kw'] as num).toDouble(),
        hourlyWage: (m['hourly_wage'] as num).toDouble(),
        marginPercent: (m['margin_percent'] as num).toDouble(),
        includeLabour: (m['include_labour'] as int) == 1,
        currencySymbol: m['currency_symbol'] as String,
        activePantryId: ((m['active_pantry_id'] ?? 1) as num).toInt(),
      );
}
