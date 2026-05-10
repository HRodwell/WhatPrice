import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';

class IngredientEditScreen extends StatefulWidget {
  const IngredientEditScreen({super.key, this.ingredient});
  final Ingredient? ingredient;

  @override
  State<IngredientEditScreen> createState() => _IngredientEditScreenState();
}

class _IngredientEditScreenState extends State<IngredientEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _packSize;
  late final TextEditingController _packCost;
  late Unit _unit;

  @override
  void initState() {
    super.initState();
    final i = widget.ingredient;
    _name = TextEditingController(text: i?.name ?? '');
    _packSize = TextEditingController(
        text: i == null ? '' : num2(i.packSize));
    _packCost = TextEditingController(
        text: i == null ? '' : i.packCost.toStringAsFixed(2));
    _unit = i?.unit ?? Unit.gram;
  }

  @override
  void dispose() {
    _name.dispose();
    _packSize.dispose();
    _packCost.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final ing = Ingredient(
      id: widget.ingredient?.id,
      name: _name.text.trim(),
      unit: _unit,
      packSize: double.parse(_packSize.text),
      packCost: double.parse(_packCost.text),
    );
    await state.upsertIngredient(ing);
    if (mounted) Navigator.of(context).pop();
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
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _packSize,
                  decoration: InputDecoration(
                      labelText: 'Pack size (${_unit.short})'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: _positiveNumber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _packCost,
                  decoration: const InputDecoration(labelText: 'Pack cost'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: _positiveNumber,
                ),
              ),
            ]),
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

  String? _positiveNumber(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final d = double.tryParse(v);
    if (d == null) return 'Number';
    if (d <= 0) return 'Must be > 0';
    return null;
  }
}
