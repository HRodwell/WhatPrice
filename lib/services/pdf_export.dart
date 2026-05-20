import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../allergens.dart';
import '../cost.dart';
import '../format.dart';
import '../models.dart';
import 'image_storage.dart';

class RecipePdfInput {
  final Recipe recipe;
  final List<RecipeIngredient> lines;
  final List<RecipeImage> images;
  final Map<int, Ingredient> ingredientsById;
  final Map<int, IngredientPrice> pricesByIngredientId;
  final AppSettings settings;
  final String pantryName;
  final RecipeCostSnapshot? snapshot;

  const RecipePdfInput({
    required this.recipe,
    required this.lines,
    required this.images,
    required this.ingredientsById,
    required this.pricesByIngredientId,
    required this.settings,
    required this.pantryName,
    required this.snapshot,
  });
}

Future<Uint8List> buildRecipePdf(RecipePdfInput input) async {
  final doc = pw.Document();
  final symbol = input.settings.currencySymbol;
  final breakdown = computeCost(
    recipe: input.recipe,
    lines: input.lines,
    ingredientsById: input.ingredientsById,
    pricesByIngredientId: input.pricesByIngredientId,
    settings: input.settings,
    marginOverride: input.snapshot?.marginPercent,
    includeLabourOverride: input.snapshot?.includeLabour,
  );
  final allergens = allergensFor(input.lines, input.ingredientsById);
  final imageWidgets = await _loadImageWidgets(input.images);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) => [
        pw.Text(
          input.recipe.name,
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Pantry: ${input.pantryName}',
          style: const pw.TextStyle(color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Yield: ${input.recipe.yieldPieces}   '
          'Bake: ${num2(input.recipe.ovenMinutes)} min   '
          'Labour: ${num2(input.recipe.labourMinutes)} min',
          style: const pw.TextStyle(color: PdfColors.grey700),
        ),
        if (allergens.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          _allergenRow(allergens),
        ],
        if (imageWidgets.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          _imageGrid(imageWidgets),
        ],
        if (breakdown.hasMissingPrices) ...[
          pw.SizedBox(height: 14),
          _missingPricesBanner(
            count: breakdown.missingPriceIngredientIds.length,
            pantryName: input.pantryName,
          ),
        ],
        pw.SizedBox(height: 20),
        pw.Header(level: 1, text: 'Ingredients'),
        _ingredientsTable(
          input.lines,
          input.ingredientsById,
          input.pricesByIngredientId,
          symbol,
        ),
        if (input.recipe.notes != null &&
            input.recipe.notes!.trim().isNotEmpty) ...[
          pw.SizedBox(height: 20),
          pw.Header(level: 1, text: 'Notes'),
          pw.Text(input.recipe.notes!),
        ],
        pw.SizedBox(height: 20),
        pw.Header(level: 1, text: 'Cost'),
        _costSummary(breakdown, symbol),
      ],
    ),
  );

  return doc.save();
}

Future<List<pw.Widget>> _loadImageWidgets(List<RecipeImage> images) async {
  final out = <pw.Widget>[];
  for (final img in images) {
    final file = await ImageStorage.instance.resolveAsync(img.path);
    if (!await file.exists()) continue;
    final bytes = await File(file.path).readAsBytes();
    out.add(
      pw.ClipRRect(
        horizontalRadius: 8,
        verticalRadius: 8,
        child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
      ),
    );
  }
  return out;
}

pw.Widget _imageGrid(List<pw.Widget> images) {
  if (images.length == 1) {
    return pw.SizedBox(height: 220, child: images.first);
  }
  return pw.GridView(
    crossAxisCount: 2,
    childAspectRatio: 1.4,
    crossAxisSpacing: 8,
    mainAxisSpacing: 8,
    children: images,
  );
}

pw.Widget _allergenRow(AllergenSet allergens) {
  return pw.Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final a in allergens.values)
        pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: const pw.BoxDecoration(
            color: PdfColors.red50,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(
            a.label,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.red800,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
    ],
  );
}

pw.Widget _missingPricesBanner({
  required int count,
  required String pantryName,
}) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: const pw.BoxDecoration(
      color: PdfColors.red50,
      borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Text(
      count == 1
          ? '1 ingredient has no price in $pantryName — cost treated as 0.'
          : '$count ingredients have no price in $pantryName — costs treated as 0.',
      style: const pw.TextStyle(color: PdfColors.red900),
    ),
  );
}

pw.Widget _ingredientsTable(
  List<RecipeIngredient> lines,
  Map<int, Ingredient> byId,
  Map<int, IngredientPrice> priceById,
  String symbol,
) {
  final headerStyle = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  return pw.Table(
    border: pw.TableBorder.symmetric(
      inside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5),
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(3),
      1: pw.FlexColumnWidth(1),
      2: pw.FlexColumnWidth(1.5),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey100),
        children: [
          _cell('Ingredient', style: headerStyle),
          _cell('Quantity', style: headerStyle, align: pw.TextAlign.right),
          _cell('Line cost', style: headerStyle, align: pw.TextAlign.right),
        ],
      ),
      for (final line in lines)
        pw.TableRow(children: [
          _cell(byId[line.ingredientId]?.name ?? 'Unknown'),
          _cell(
            '${num2(line.quantity)} ${byId[line.ingredientId]?.unit.short ?? ''}',
            align: pw.TextAlign.right,
          ),
          _cell(
            priceById[line.ingredientId] == null
                ? '—'
                : money(
                    priceById[line.ingredientId]!.unitCost * line.quantity,
                    symbol,
                  ),
            align: pw.TextAlign.right,
          ),
        ]),
    ],
  );
}

pw.Widget _cell(String text, {pw.TextStyle? style, pw.TextAlign? align}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    child: pw.Text(text, style: style, textAlign: align),
  );
}

pw.Widget _costSummary(CostBreakdown b, String symbol) {
  pw.Widget row(String label, double v, {bool bold = false, PdfColor? color}) {
    final style = pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(money(v, symbol), style: style),
        ],
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      row('Ingredients', b.ingredientsCost),
      row('Energy', b.energyCost),
      if (b.labourCost > 0) row('Labour', b.labourCost),
      pw.Divider(),
      row('Total batch', b.totalCost, bold: true),
      row('Per piece', b.costPerPiece, bold: true),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: const pw.BoxDecoration(
          color: PdfColors.amber50,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Suggested price (${num2(b.marginPercent)}% margin)',
              style: const pw.TextStyle(color: PdfColors.amber800),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              '${money(b.suggestedPricePerPiece, symbol)} per piece    '
              '${money(b.suggestedBatchPrice, symbol)} per batch',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.amber900,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
