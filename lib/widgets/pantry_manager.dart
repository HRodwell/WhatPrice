import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';

class PantryManager extends StatelessWidget {
  const PantryManager({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(
      children: [
        for (final p in state.pantries)
          _PantryTile(
            pantry: p,
            isLast: state.pantries.length <= 1,
          ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showRenameDialog(context, null),
            icon: const Icon(Icons.add),
            label: const Text('Add pantry'),
          ),
        ),
      ],
    );
  }
}

class _PantryTile extends StatelessWidget {
  const _PantryTile({required this.pantry, required this.isLast});
  final Pantry pantry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.kitchen_outlined),
      title: Text(pantry.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showRenameDialog(context, pantry),
          ),
          IconButton(
            tooltip: isLast ? 'Cannot delete last pantry' : 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: isLast ? null : () => _confirmDelete(context, pantry),
          ),
        ],
      ),
    );
  }
}

Future<void> _showRenameDialog(BuildContext context, Pantry? existing) async {
  final controller = TextEditingController(text: existing?.name ?? '');
  final state = context.read<AppState>();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'New pantry' : 'Rename pantry'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Name'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(existing == null ? 'Add' : 'Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.isEmpty) return;
  await state.upsertPantry(
    existing == null ? Pantry(name: result) : existing.copyWith(name: result),
  );
}

Future<void> _confirmDelete(BuildContext context, Pantry pantry) async {
  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete ${pantry.name}?'),
      content: const Text(
          'This removes the pantry, its prices, and its saved calculations. '
          'Recipes and ingredients are not deleted.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true || pantry.id == null) return;
  try {
    await state.deletePantry(pantry.id!);
  } on StateError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}
