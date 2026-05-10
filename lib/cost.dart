import 'models.dart';

class LineCost {
  final RecipeIngredient line;
  final Ingredient ingredient;
  final double cost;
  const LineCost(this.line, this.ingredient, this.cost);
}

class CostBreakdown {
  final List<LineCost> lines;
  final double ingredientsCost;
  final double energyCost;
  final double labourCost;
  final int yieldPieces;
  final double marginPercent;

  const CostBreakdown({
    required this.lines,
    required this.ingredientsCost,
    required this.energyCost,
    required this.labourCost,
    required this.yieldPieces,
    required this.marginPercent,
  });

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
  required AppSettings settings,
}) {
  final lineCosts = <LineCost>[];
  double ingredientsCost = 0;
  for (final line in lines) {
    final ing = ingredientsById[line.ingredientId];
    if (ing == null) continue;
    final c = ing.unitCost * line.quantity;
    ingredientsCost += c;
    lineCosts.add(LineCost(line, ing, c));
  }

  final energyKwh = (recipe.ovenMinutes / 60.0) * settings.ovenKw;
  final energyCost = energyKwh * settings.electricityRatePerKwh;
  final labourCost = settings.includeLabour
      ? (recipe.labourMinutes / 60.0) * settings.hourlyWage
      : 0.0;

  return CostBreakdown(
    lines: lineCosts,
    ingredientsCost: ingredientsCost,
    energyCost: energyCost,
    labourCost: labourCost,
    yieldPieces: recipe.yieldPieces,
    marginPercent: settings.marginPercent,
  );
}
