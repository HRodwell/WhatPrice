import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cost.dart';
import '../format.dart';
import '../models.dart';

class CalculateScreen extends StatefulWidget {
  const CalculateScreen({super.key});

  @override
  State<CalculateScreen> createState() => _CalculateScreenState();
}

class _CalculateScreenState extends State<CalculateScreen> {
  int? _recipeId;
  int? _lastSeenPantryId;
  late TextEditingController _margin;
  bool _includeLabour = true;
  List<RecipeIngredient> _lines = [];
  bool _linesLoaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _margin = TextEditingController();
  }

  @override
  void dispose() {
    _margin.dispose();
    super.dispose();
  }

  void _selectRecipe(AppState state, int? id) {
    if (id == null) {
      setState(() {
        _recipeId = null;
        _lines = [];
        _linesLoaded = false;
      });
      return;
    }
    final snap = state.snapshotOf(id);
    setState(() {
      _recipeId = id;
      _margin.text = num2(snap?.marginPercent ?? state.settings.marginPercent);
      _includeLabour = snap?.includeLabour ?? state.settings.includeLabour;
      _linesLoaded = false;
      _lines = [];
    });
    _loadLines(state, id);
  }

  Future<void> _loadLines(AppState state, int id) async {
    final lines = await state.loadRecipeLines(id);
    if (!mounted || _recipeId != id) return;
    setState(() {
      _lines = lines;
      _linesLoaded = true;
    });
  }

  Recipe? _currentRecipe(AppState state) {
    if (_recipeId == null) return null;
    return state.recipes.firstWhere(
      (r) => r.id == _recipeId,
      orElse: () => state.recipes.first,
    );
  }

  Future<void> _save(BuildContext context, Recipe recipe) async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final margin = double.tryParse(_margin.text);
    if (margin == null || margin < 0 || margin >= 100) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Margin must be 0–99.9')),
      );
      return;
    }
    final breakdown = computeCost(
      recipe: recipe,
      lines: _lines,
      ingredientsById: state.ingredientsById,
      pricesByIngredientId: state.pricesForPantry(state.activePantryId),
      settings: state.settings,
      marginOverride: margin,
      includeLabourOverride: _includeLabour,
    );
    setState(() => _saving = true);
    try {
      await state.saveSnapshot(RecipeCostSnapshot(
        recipeId: recipe.id!,
        pantryId: state.activePantryId,
        marginPercent: margin,
        includeLabour: _includeLabour,
        ingredientsCost: breakdown.ingredientsCost,
        energyCost: breakdown.energyCost,
        labourCost: breakdown.labourCost,
        costPerPiece: breakdown.costPerPiece,
        suggestedPricePerPiece: breakdown.suggestedPricePerPiece,
        suggestedBatchPrice: breakdown.suggestedBatchPrice,
        computedAt: DateTime.now(),
      ));
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved calculation for ${state.activePantry.name}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final recipes = state.recipes;
    if (recipes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Add a recipe before you can calculate prices.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Re-seed margin/labour when the active pantry changes.
    if (_lastSeenPantryId != state.activePantryId && _recipeId != null) {
      final snap = state.snapshotOf(_recipeId!);
      _lastSeenPantryId = state.activePantryId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _margin.text =
              num2(snap?.marginPercent ?? state.settings.marginPercent);
          _includeLabour =
              snap?.includeLabour ?? state.settings.includeLabour;
        });
      });
    }

    if (_recipeId == null || !recipes.any((r) => r.id == _recipeId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectRecipe(state, recipes.first.id);
      });
    }

    final recipe = _currentRecipe(state);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Costing for ${state.activePantry.name}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        DropdownButtonFormField<int>(
          initialValue: _recipeId,
          decoration: const InputDecoration(labelText: 'Recipe'),
          isExpanded: true,
          items: [
            for (final r in recipes)
              DropdownMenuItem(
                value: r.id,
                child: Text(r.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (id) => _selectRecipe(state, id),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _margin,
          decoration: const InputDecoration(
            labelText: 'Margin (%)',
            helperText: 'Sale = cost / (1 - margin)',
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include labour'),
          subtitle: Text(
            recipe == null
                ? ''
                : 'Labour time: ${num2(recipe.labourMinutes)} min',
          ),
          value: _includeLabour,
          onChanged: (v) => setState(() => _includeLabour = v),
        ),
        const SizedBox(height: 16),
        if (recipe != null && _linesLoaded)
          _Breakdown(
            recipe: recipe,
            lines: _lines,
            margin: double.tryParse(_margin.text) ?? state.settings.marginPercent,
            includeLabour: _includeLabour,
          )
        else
          const Center(child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          )),
        if (recipe != null) ...[
          const SizedBox(height: 16),
          if (state.snapshotOf(recipe.id!) != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Last saved for ${state.activePantry.name}: '
                '${DateFormat.yMd().add_jm().format(state.snapshotOf(recipe.id!)!.computedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          FilledButton.icon(
            onPressed: _saving || !_linesLoaded
                ? null
                : () => _save(context, recipe),
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save calculation'),
          ),
        ],
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({
    required this.recipe,
    required this.lines,
    required this.margin,
    required this.includeLabour,
  });

  final Recipe recipe;
  final List<RecipeIngredient> lines;
  final double margin;
  final bool includeLabour;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final symbol = state.settings.currencySymbol;
    final breakdown = computeCost(
      recipe: recipe,
      lines: lines,
      ingredientsById: state.ingredientsById,
      pricesByIngredientId: state.pricesForPantry(state.activePantryId),
      settings: state.settings,
      marginOverride: margin,
      includeLabourOverride: includeLabour,
    );
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cost breakdown',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (breakdown.hasMissingPrices) ...[
              _MissingPricesWarning(
                count: breakdown.missingPriceIngredientIds.length,
                pantryName: state.activePantry.name,
              ),
              const SizedBox(height: 12),
            ],
            _row(context, 'Ingredients', breakdown.ingredientsCost, symbol),
            _row(context, 'Energy', breakdown.energyCost, symbol),
            if (breakdown.labourCost > 0)
              _row(context, 'Labour', breakdown.labourCost, symbol),
            const Divider(height: 24),
            _row(context, 'Total batch', breakdown.totalCost, symbol, bold: true),
            _row(context, 'Per piece', breakdown.costPerPiece, symbol, bold: true),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_offer_outlined,
                      color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggested price (${num2(margin)}% margin)',
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${money(breakdown.suggestedPricePerPiece, symbol)} per piece   ·   ${money(breakdown.suggestedBatchPrice, symbol)} per batch',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, double v, String symbol,
      {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: bold ? 15 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(money(v, symbol), style: style),
        ],
      ),
    );
  }
}

class _MissingPricesWarning extends StatelessWidget {
  const _MissingPricesWarning({required this.count, required this.pantryName});
  final int count;
  final String pantryName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? '1 ingredient has no price in $pantryName — its cost is treated as 0.'
                  : '$count ingredients have no price in $pantryName — their costs are treated as 0.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
