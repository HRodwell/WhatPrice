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

class Ingredient {
  final int? id;
  final String name;
  final Unit unit;
  final double packSize;
  final double packCost;

  const Ingredient({
    this.id,
    required this.name,
    required this.unit,
    required this.packSize,
    required this.packCost,
  });

  double get unitCost => packSize == 0 ? 0 : packCost / packSize;

  Ingredient copyWith({
    int? id,
    String? name,
    Unit? unit,
    double? packSize,
    double? packCost,
  }) =>
      Ingredient(
        id: id ?? this.id,
        name: name ?? this.name,
        unit: unit ?? this.unit,
        packSize: packSize ?? this.packSize,
        packCost: packCost ?? this.packCost,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'unit': unit.name,
        'pack_size': packSize,
        'pack_cost': packCost,
      };

  factory Ingredient.fromMap(Map<String, Object?> m) => Ingredient(
        id: m['id'] as int?,
        name: m['name'] as String,
        unit: UnitX.parse(m['unit'] as String),
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

class AppSettings {
  final double electricityRatePerKwh;
  final double ovenKw;
  final double hourlyWage;
  final double marginPercent;
  final bool includeLabour;
  final String currencySymbol;

  const AppSettings({
    required this.electricityRatePerKwh,
    required this.ovenKw,
    required this.hourlyWage,
    required this.marginPercent,
    required this.includeLabour,
    required this.currencySymbol,
  });

  static const defaults = AppSettings(
    electricityRatePerKwh: 0.30,
    ovenKw: 2.5,
    hourlyWage: 20.0,
    marginPercent: 60.0,
    includeLabour: true,
    currencySymbol: '\$',
  );

  AppSettings copyWith({
    double? electricityRatePerKwh,
    double? ovenKw,
    double? hourlyWage,
    double? marginPercent,
    bool? includeLabour,
    String? currencySymbol,
  }) =>
      AppSettings(
        electricityRatePerKwh:
            electricityRatePerKwh ?? this.electricityRatePerKwh,
        ovenKw: ovenKw ?? this.ovenKw,
        hourlyWage: hourlyWage ?? this.hourlyWage,
        marginPercent: marginPercent ?? this.marginPercent,
        includeLabour: includeLabour ?? this.includeLabour,
        currencySymbol: currencySymbol ?? this.currencySymbol,
      );

  Map<String, Object?> toMap() => {
        'id': 1,
        'electricity_rate': electricityRatePerKwh,
        'oven_kw': ovenKw,
        'hourly_wage': hourlyWage,
        'margin_percent': marginPercent,
        'include_labour': includeLabour ? 1 : 0,
        'currency_symbol': currencySymbol,
      };

  factory AppSettings.fromMap(Map<String, Object?> m) => AppSettings(
        electricityRatePerKwh: (m['electricity_rate'] as num).toDouble(),
        ovenKw: (m['oven_kw'] as num).toDouble(),
        hourlyWage: (m['hourly_wage'] as num).toDouble(),
        marginPercent: (m['margin_percent'] as num).toDouble(),
        includeLabour: (m['include_labour'] as int) == 1,
        currencySymbol: m['currency_symbol'] as String,
      );
}
