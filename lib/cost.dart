import 'allergens.dart';
import 'models.dart';

AllergenSet allergensFor(
  List<RecipeIngredient> lines,
  Map<int, Ingredient> ingredientsById,
) {
  var s = AllergenSet.empty;
  for (final line in lines) {
    final ing = ingredientsById[line.ingredientId];
    if (ing != null) s = s.union(ing.allergens);
  }
  return s;
}

class LineCost {
  final RecipeIngredient line;
  final Ingredient? ingredient;
  final IngredientPrice? price;
  final double cost;
  bool get missing => price == null;
  const LineCost({
    required this.line,
    required this.ingredient,
    required this.price,
    required this.cost,
  });
}

class CostBreakdown {
  final List<LineCost> lines;
  final double ingredientsCost;
  final double energyCost;
  final double labourCost;
  final int yieldPieces;
  final double marginPercent;
  final List<int> missingPriceIngredientIds;

  const CostBreakdown({
    required this.lines,
    required this.ingredientsCost,
    required this.energyCost,
    required this.labourCost,
    required this.yieldPieces,
    required this.marginPercent,
    required this.missingPriceIngredientIds,
  });

  bool get hasMissingPrices => missingPriceIngredientIds.isNotEmpty;

  double get totalCost => ingredientsCost + energyCost + labourCost;
  double get costPerPiece => yieldPieces == 0 ? 0 : totalCost / yieldPieces;

  double get suggestedPricePerPiece {
    final m = marginPercent.clamp(0, 99.9) / 100;
    return m >= 1 ? costPerPiece : costPerPiece / (1 - m);
  }

  double get suggestedBatchPrice => suggestedPricePerPiece * yieldPieces;
}

CostBreakdown computeCost({
  required Recipe recipe,
  required List<RecipeIngredient> lines,
  required Map<int, Ingredient> ingredientsById,
  required Map<int, IngredientPrice> pricesByIngredientId,
  required AppSettings settings,
  double? marginOverride,
  bool? includeLabourOverride,
}) {
  final lineCosts = <LineCost>[];
  final missing = <int>[];
  double ingredientsCost = 0;
  for (final line in lines) {
    final ing = ingredientsById[line.ingredientId];
    final price = pricesByIngredientId[line.ingredientId];
    final unitCost = price?.unitCost ?? 0;
    final c = unitCost * line.quantity;
    ingredientsCost += c;
    if (price == null && ing != null) missing.add(line.ingredientId);
    lineCosts.add(LineCost(
      line: line,
      ingredient: ing,
      price: price,
      cost: c,
    ));
  }

  final energyKwh = (recipe.ovenMinutes / 60.0) * settings.ovenKw;
  final energyCost = energyKwh * settings.electricityRatePerKwh;
  final useLabour = includeLabourOverride ?? settings.includeLabour;
  final labourCost = useLabour
      ? (recipe.labourMinutes / 60.0) * settings.hourlyWage
      : 0.0;

  return CostBreakdown(
    lines: lineCosts,
    ingredientsCost: ingredientsCost,
    energyCost: energyCost,
    labourCost: labourCost,
    yieldPieces: recipe.yieldPieces,
    marginPercent: marginOverride ?? settings.marginPercent,
    missingPriceIngredientIds: missing,
  );
}
