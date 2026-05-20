import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../allergens.dart';
import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/allergen_chips.dart';

class IngredientEditScreen extends StatefulWidget {
  const IngredientEditScreen({super.key, this.ingredient});
  final Ingredient? ingredient;

  @override
  State<IngredientEditScreen> createState() => _IngredientEditScreenState();
}

class _IngredientEditScreenState extends State<IngredientEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late Unit _unit;
  late AllergenSet _allergens;

  final Map<int, TextEditingController> _packSizeCtrls = {};
  final Map<int, TextEditingController> _packCostCtrls = {};
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    final i = widget.ingredient;
    _name = TextEditingController(text: i?.name ?? '');
    _unit = i?.unit ?? Unit.gram;
    _allergens = i?.allergens ?? AllergenSet.empty;
  }

  void _hydratePriceFields(AppState state) {
    if (_hydrated) return;
    final id = widget.ingredient?.id;
    for (final p in state.pantries) {
      if (p.id == null) continue;
      final price = id == null ? null : state.priceFor(id, pantryId: p.id);
      _packSizeCtrls[p.id!] =
          TextEditingController(text: price == null ? '' : num2(price.packSize));
      _packCostCtrls[p.id!] = TextEditingController(
          text: price == null ? '' : price.packCost.toStringAsFixed(2));
    }
    _hydrated = true;
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _packSizeCtrls.values) {
      c.dispose();
    }
    for (final c in _packCostCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);

    final ing = Ingredient(
      id: widget.ingredient?.id,
      name: _name.text.trim(),
      unit: _unit,
      allergens: _allergens,
    );
    final ingredientId = await state.upsertIngredient(ing);

    for (final p in state.pantries) {
      if (p.id == null) continue;
      final sizeText = _packSizeCtrls[p.id]?.text.trim() ?? '';
      final costText = _packCostCtrls[p.id]?.text.trim() ?? '';
      if (sizeText.isEmpty && costText.isEmpty) {
        await state.deletePrice(ingredientId, p.id!);
        continue;
      }
      final size = double.tryParse(sizeText);
      final cost = double.tryParse(costText);
      if (size == null || cost == null || size <= 0 || cost < 0) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Invalid price for ${p.name}: both pack size and cost required.',
          ),
        ));
        return;
      }
      await state.upsertPrice(IngredientPrice(
        ingredientId: ingredientId,
        pantryId: p.id!,
        packSize: size,
        packCost: cost,
      ));
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.ingredient?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete ingredient?'),
        content: Text(
            'Recipes still using "${widget.ingredient!.name}" will block deletion.'),
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
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final state = context.read<AppState>();
    try {
      await state.deleteIngredient(id);
      navigator.pop();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Cannot delete: still used in a recipe.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _hydratePriceFields(state);
    final isNew = widget.ingredient == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New ingredient' : 'Edit ingredient'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Unit>(
              initialValue: _unit,
              decoration: const InputDecoration(labelText: 'Unit'),
              items: Unit.values
                  .map((u) =>
                      DropdownMenuItem(value: u, child: Text(u.label)))
                  .toList(),
              onChanged: (u) => setState(() => _unit = u ?? Unit.gram),
            ),
            const SizedBox(height: 24),
            Text('Prices per pantry',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Leave blank if you don’t stock this ingredient in that pantry.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final p in state.pantries)
              _PantryPriceRow(
                pantry: p,
                unitShort: _unit.short,
                sizeController: _packSizeCtrls[p.id]!,
                costController: _packCostCtrls[p.id]!,
              ),
            const SizedBox(height: 24),
            Text('Allergens', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            AllergenSelector(
              value: _allergens,
              onChanged: (v) => setState(() => _allergens = v),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PantryPriceRow extends StatelessWidget {
  const _PantryPriceRow({
    required this.pantry,
    required this.unitShort,
    required this.sizeController,
    required this.costController,
  });

  final Pantry pantry;
  final String unitShort;
  final TextEditingController sizeController;
  final TextEditingController costController;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pantry.name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: sizeController,
                decoration: InputDecoration(labelText: 'Pack size ($unitShort)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: costController,
                decoration: const InputDecoration(labelText: 'Pack cost'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
