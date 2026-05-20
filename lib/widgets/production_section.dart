import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';

class ProductionSection extends StatelessWidget {
  const ProductionSection({super.key, required this.recipeId});
  final int recipeId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sessions = state.productionSessionsOf(recipeId);
    final batches = state.productionBatchesOf(recipeId);
    final last = state.lastProductionAt(recipeId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Production history',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: () => _markMade(context, recipeId),
              icon: const Icon(Icons.add),
              label: const Text('Mark made'),
            ),
          ],
        ),
        Text(
          sessions == 0
              ? 'Never made yet.'
              : 'Made $sessions ${sessions == 1 ? 'time' : 'times'}'
                  ' · $batches ${batches == 1 ? 'batch' : 'batches'}'
                  '${last == null ? '' : '   ·   last ${DateFormat.yMMMd().format(last)}'}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (sessions > 0)
          _RecentProductionsList(recipeId: recipeId),
      ],
    );
  }
}

class _RecentProductionsList extends StatefulWidget {
  const _RecentProductionsList({required this.recipeId});
  final int recipeId;

  @override
  State<_RecentProductionsList> createState() => _RecentProductionsListState();
}

class _RecentProductionsListState extends State<_RecentProductionsList> {
  static const _limit = 5;
  bool _showAll = false;
  Future<List<ProductionRecord>>? _future;
  int _aggregateSignature = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sig = state.productionSessionsOf(widget.recipeId) * 1000 +
        state.productionBatchesOf(widget.recipeId);
    if (_future == null || sig != _aggregateSignature) {
      _aggregateSignature = sig;
      _future = state.loadProductions(widget.recipeId);
    }
    return FutureBuilder<List<ProductionRecord>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final all = snap.data!;
        final shown = _showAll ? all : all.take(_limit).toList();
        return Column(
          children: [
            const SizedBox(height: 8),
            for (final p in shown)
              _ProductionTile(
                production: p,
                pantryName: _pantryName(state, p.pantryId),
                currencySymbol: state.settings.currencySymbol,
              ),
            if (all.length > _limit)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll
                      ? 'Show less'
                      : 'Show all ${all.length} entries'),
                ),
              ),
          ],
        );
      },
    );
  }

  String _pantryName(AppState state, int pantryId) {
    return state.pantries
        .firstWhere(
          (p) => p.id == pantryId,
          orElse: () => Pantry(id: pantryId, name: 'Pantry $pantryId'),
        )
        .name;
  }
}

class _ProductionTile extends StatelessWidget {
  const _ProductionTile({
    required this.production,
    required this.pantryName,
    required this.currencySymbol,
  });
  final ProductionRecord production;
  final String pantryName;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat.yMMMd().add_jm().format(production.madeAt);
    final cost = production.costPerPiece;
    return Card(
      child: ListTile(
        dense: true,
        title: Text(
            '${production.batches} ${production.batches == 1 ? 'batch' : 'batches'} · $pantryName'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(dateText),
            if (cost != null)
              Text(
                'Cost per piece at time of making: ${money(cost, currencySymbol)}',
              ),
            if (production.notes != null && production.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(production.notes!,
                    style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
          ],
        ),
        trailing: IconButton(
          tooltip: 'Delete entry',
          icon: const Icon(Icons.close),
          onPressed: () => _confirmDelete(context, production),
        ),
      ),
    );
  }
}

Future<void> _confirmDelete(
    BuildContext context, ProductionRecord production) async {
  final state = context.read<AppState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Delete entry?'),
      content: const Text('This removes one production record.'),
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
  if (ok != true || production.id == null) return;
  await state.deleteProduction(production.id!);
}

Future<void> _markMade(BuildContext context, int recipeId) async {
  final state = context.read<AppState>();
  final result = await showDialog<_NewProduction>(
    context: context,
    builder: (_) => _MarkMadeDialog(activePantryName: state.activePantry.name),
  );
  if (result == null) return;
  final snapshot = state.snapshotOf(recipeId);
  await state.upsertProduction(ProductionRecord(
    recipeId: recipeId,
    pantryId: state.activePantryId,
    madeAt: result.madeAt,
    batches: result.batches,
    costPerPiece: snapshot?.costPerPiece,
    notes: result.notes,
  ));
}

class _NewProduction {
  final DateTime madeAt;
  final int batches;
  final String? notes;
  const _NewProduction({
    required this.madeAt,
    required this.batches,
    this.notes,
  });
}

class _MarkMadeDialog extends StatefulWidget {
  const _MarkMadeDialog({required this.activePantryName});
  final String activePantryName;

  @override
  State<_MarkMadeDialog> createState() => _MarkMadeDialogState();
}

class _MarkMadeDialogState extends State<_MarkMadeDialog> {
  DateTime _date = DateTime.now();
  int _batches = 1;
  final _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateTime(
          _date.year,
          _date.month,
          _date.day,
          picked.hour,
          picked.minute,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mark recipe made'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pantry: ${widget.activePantryName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(DateFormat.yMd().format(_date)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time),
                    label: Text(DateFormat.jm().format(_date)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Batches'),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _batches > 1
                    ? () => setState(() => _batches--)
                    : null,
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '$_batches',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _batches++),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Save'),
          onPressed: () => Navigator.pop(
            context,
            _NewProduction(
              madeAt: _date,
              batches: _batches,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          ),
        ),
      ],
    );
  }
}
