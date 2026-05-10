import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cost.dart';
import '../format.dart';
import '../models.dart';

class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key, this.recipe});
  final Recipe? recipe;

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _yield;
  late final TextEditingController _oven;
  late final TextEditingController _labour;
  late final TextEditingController _notes;

  List<RecipeIngredient> _lines = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    _name = TextEditingController(text: r?.name ?? '');
    _yield = TextEditingController(text: r == null ? '12' : '${r.yieldPieces}');
    _oven = TextEditingController(text: r == null ? '15' : num2(r.ovenMinutes));
    _labour = TextEditingController(
        text: r == null ? '20' : num2(r.labourMinutes));
    _notes = TextEditingController(text: r?.notes ?? '');
    _loadLines();
  }

  Future<void> _loadLines() async {
    final r = widget.recipe;
    if (r?.id != null) {
      _lines = await context.read<AppState>().loadRecipeLines(r!.id!);
    }
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _yield.dispose();
    _oven.dispose();
    _labour.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final recipe = Recipe(
      id: widget.recipe?.id,
      name: _name.text.trim(),
      yieldPieces: int.parse(_yield.text),
      ovenMinutes: double.parse(_oven.text),
      labourMinutes: double.parse(_labour.text),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final id = await state.upsertRecipe(recipe);
    await state.replaceRecipeLines(id, _lines);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.recipe?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete recipe?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    await context.read<AppState>().deleteRecipe(id);
    navigator.pop();
  }

  Future<void> _addOrEditLine([RecipeIngredient? existing]) async {
    final state = context.read<AppState>();
    if (state.ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add ingredients first.')),
      );
      return;
    }
    final result = await showModalBottomSheet<RecipeIngredient>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IngredientLineSheet(
        ingredients: state.ingredients,
        existing: existing,
      ),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final i = _lines.indexOf(existing);
        if (i >= 0) _lines[i] = result;
      } else {
        _lines.add(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isNew = widget.recipe == null;
    final symbol = state.settings.currencySymbol;

    final breakdown = _loaded
        ? computeCost(
            recipe: Recipe(
              name: _name.text,
              yieldPieces: int.tryParse(_yield.text) ?? 1,
              ovenMinutes: double.tryParse(_oven.text) ?? 0,
              labourMinutes: double.tryParse(_labour.text) ?? 0,
            ),
            lines: _lines,
            ingredientsById: state.ingredientsById,
            settings: state.settings,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New recipe' : 'Edit recipe'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              onChanged: () => setState(() {}),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Recipe name'),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _yield,
                        decoration: const InputDecoration(
                            labelText: 'Yield (pieces)'),
                        keyboardType: TextInputType.number,
                        validator: _positiveInt,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _oven,
                        decoration: const InputDecoration(
                            labelText: 'Bake time (min)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _nonNegative,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _labour,
                    decoration: InputDecoration(
                      labelText: 'Labour time (min)',
                      helperText: state.settings.includeLabour
                          ? null
                          : 'Disabled in Settings',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _nonNegative,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: 'Ingredients',
                    trailing: TextButton.icon(
                      onPressed: () => _addOrEditLine(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ),
                  if (_lines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No ingredients added.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  else
                    ..._lines.map((line) {
                      final ing = state.ingredientsById[line.ingredientId];
                      final cost =
                          (ing?.unitCost ?? 0) * line.quantity;
                      return Card(
                        child: ListTile(
                          title: Text(ing?.name ?? 'Unknown'),
                          subtitle: Text(
                            '${num2(line.quantity)} ${ing?.unit.short ?? ''}   ·   ${money(cost, symbol)}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _lines.remove(line)),
                          ),
                          onTap: () => _addOrEditLine(line),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  if (breakdown != null)
                    _CostSummary(breakdown: breakdown, symbol: symbol),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _loaded ? _save : null,
            icon: const Icon(Icons.check),
            label: const Text('Save recipe'),
          ),
        ),
      ),
    );
  }

  String? _positiveInt(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = int.tryParse(v);
    if (n == null || n <= 0) return '> 0';
    return null;
  }

  String? _nonNegative(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = double.tryParse(v);
    if (n == null || n < 0) return '≥ 0';
    return null;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _CostSummary extends StatelessWidget {
  const _CostSummary({required this.breakdown, required this.symbol});
  final CostBreakdown breakdown;
  final String symbol;

  @override
  Widget build(BuildContext context) {
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
            _row('Ingredients', breakdown.ingredientsCost, symbol),
            _row('Energy', breakdown.energyCost, symbol),
            if (breakdown.labourCost > 0)
              _row('Labour', breakdown.labourCost, symbol),
            const Divider(height: 24),
            _row('Total batch', breakdown.totalCost, symbol, bold: true),
            _row('Per piece', breakdown.costPerPiece, symbol, bold: true),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_offer_outlined, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggested price (${num2(breakdown.marginPercent)}% margin)',
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

  Widget _row(String label, double v, String s, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: bold ? 15 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(money(v, s), style: style),
        ],
      ),
    );
  }
}

class _IngredientLineSheet extends StatefulWidget {
  const _IngredientLineSheet({required this.ingredients, this.existing});
  final List<Ingredient> ingredients;
  final RecipeIngredient? existing;

  @override
  State<_IngredientLineSheet> createState() => _IngredientLineSheetState();
}

class _IngredientLineSheetState extends State<_IngredientLineSheet> {
  late int _ingredientId;
  late TextEditingController _qty;

  @override
  void initState() {
    super.initState();
    _ingredientId = widget.existing?.ingredientId ?? widget.ingredients.first.id!;
    _qty = TextEditingController(
      text: widget.existing == null ? '' : num2(widget.existing!.quantity),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.ingredients.firstWhere(
      (i) => i.id == _ingredientId,
      orElse: () => widget.ingredients.first,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'Add ingredient' : 'Edit ingredient',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _ingredientId,
            decoration: const InputDecoration(labelText: 'Ingredient'),
            isExpanded: true,
            items: widget.ingredients
                .map((i) => DropdownMenuItem(
                      value: i.id,
                      child: Text(i.name, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _ingredientId = v ?? _ingredientId),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            autofocus: widget.existing == null,
            decoration: InputDecoration(
              labelText: 'Quantity',
              suffixText: selected.unit.short,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('OK'),
            onPressed: () {
              final q = double.tryParse(_qty.text);
              if (q == null || q <= 0) return;
              Navigator.of(context).pop(RecipeIngredient(
                id: widget.existing?.id,
                recipeId: widget.existing?.recipeId ?? 0,
                ingredientId: _ingredientId,
                quantity: q,
              ));
            },
          ),
        ],
      ),
    );
  }
}
