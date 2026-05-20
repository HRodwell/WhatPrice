import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cost.dart';
import '../format.dart';
import '../models.dart';
import '../services/bulk_export.dart';
import '../services/image_storage.dart';
import '../widgets/allergen_chips.dart';
import 'recipe_edit_screen.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key});

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  final Set<int> _selected = {};
  bool _exporting = false;

  bool get _selecting => _selected.isNotEmpty;

  void _toggle(int id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _enterSelection(int id) {
    setState(() => _selected.add(id));
  }

  void _exitSelection() {
    setState(_selected.clear);
  }

  void _selectAll(List<Recipe> recipes) {
    setState(() {
      _selected
        ..clear()
        ..addAll(recipes.map((r) => r.id!).whereType<int>());
    });
  }

  Future<void> _exportSelected() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final selected = state.recipes
        .where((r) => r.id != null && _selected.contains(r.id))
        .toList();
    if (selected.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final result =
          await exportRecipesAsZip(recipes: selected, state: state);
      if (!mounted) return;
      if (result.message != null) {
        messenger.showSnackBar(SnackBar(content: Text(result.message!)));
      } else if (result.savedPath != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Saved to ${result.savedPath}')),
        );
      } else if (result.ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Exported')),
        );
      }
      if (result.ok) _exitSelection();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final recipes = state.recipes;
    final allSelected =
        _selected.length == recipes.length && recipes.isNotEmpty;

    return Scaffold(
      body: Column(
        children: [
          if (_selecting)
            _SelectionBar(
              count: _selected.length,
              allSelected: allSelected,
              exporting: _exporting,
              onClose: _exitSelection,
              onSelectAll: () =>
                  allSelected ? _exitSelection() : _selectAll(recipes),
              onExport: _exporting ? null : _exportSelected,
            ),
          Expanded(
            child: recipes.isEmpty
                ? const _Empty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: recipes.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = recipes[i];
                      final selected =
                          r.id != null && _selected.contains(r.id);
                      return _RecipeCard(
                        recipe: r,
                        state: state,
                        selecting: _selecting,
                        selected: selected,
                        onTap: () {
                          if (_selecting) {
                            _toggle(r.id!);
                          } else {
                            _open(context, r);
                          }
                        },
                        onLongPress: () =>
                            r.id != null ? _enterSelection(r.id!) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _open(context, null),
              icon: const Icon(Icons.add),
              label: const Text('New recipe'),
            ),
    );
  }

  static void _open(BuildContext context, Recipe? r) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecipeEditScreen(recipe: r)),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.allSelected,
    required this.exporting,
    required this.onClose,
    required this.onSelectAll,
    required this.onExport,
  });

  final int count;
  final bool allSelected;
  final bool exporting;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
              Expanded(
                child: Text(
                  '$count selected',
                  style: TextStyle(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSelectAll,
                child: Text(allSelected ? 'None' : 'All'),
              ),
              if (exporting)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Export PDF',
                  icon: const Icon(Icons.ios_share),
                  onPressed: onExport,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({
    required this.recipe,
    required this.state,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Recipe recipe;
  final AppState state;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? scheme.primary : scheme.outline,
                  ),
                ),
              _RecipeThumbnail(path: state.firstImageOf(recipe.id!)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Yield: ${recipe.yieldPieces}   ·   Bake: ${num2(recipe.ovenMinutes)} min'
                      '${state.settings.includeLabour ? '   ·   Labour: ${num2(recipe.labourMinutes)} min' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _CostFuture(recipe: recipe, state: state),
                  ],
                ),
              ),
              if (!selecting) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _CostFuture extends StatelessWidget {
  const _CostFuture({required this.recipe, required this.state});
  final Recipe recipe;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshotOf(recipe.id!);
    final pantryName = state.activePantry.name;
    final symbol = state.settings.currencySymbol;
    final sessions = state.productionSessionsOf(recipe.id!);
    final batches = state.productionBatchesOf(recipe.id!);
    return FutureBuilder<List<RecipeIngredient>>(
      future: state.loadRecipeLines(recipe.id!),
      builder: (context, snap) {
        final allergens = snap.hasData
            ? allergensFor(snap.data!, state.ingredientsById)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (snapshot != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Chip(
                    label: 'Per piece',
                    value: money(snapshot.costPerPiece, symbol),
                  ),
                  _Chip(
                    label: 'Suggested',
                    value: money(snapshot.suggestedPricePerPiece, symbol),
                    tone: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  if (sessions > 0)
                    _Chip(
                      label: 'Made',
                      value: '$sessions×'
                          '${batches != sessions ? ' / $batches' : ''}',
                    ),
                ],
              )
            else
              Text(
                'Not calculated for $pantryName',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            if (allergens != null && allergens.isNotEmpty) ...[
              const SizedBox(height: 8),
              AllergenChipsRow(allergens: allergens, dense: true),
            ],
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value, this.tone});
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone ?? scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RecipeThumbnail extends StatelessWidget {
  const _RecipeThumbnail({required this.path});
  final String? path;

  static const double _size = 64;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(12);
    if (path == null) {
      return Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: radius,
        ),
        child: Icon(Icons.cookie_outlined,
            color: scheme.onSurfaceVariant, size: 28),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: FutureBuilder<File>(
        future: ImageStorage.instance.resolveAsync(path!),
        builder: (_, snap) {
          if (!snap.hasData) {
            return SizedBox(
              width: _size,
              height: _size,
              child: ColoredBox(color: scheme.surfaceContainerHighest),
            );
          }
          return Image.file(
            snap.data!,
            width: _size,
            height: _size,
            fit: BoxFit.cover,
            cacheWidth: 256,
            errorBuilder: (_, __, ___) => Container(
              width: _size,
              height: _size,
              color: scheme.surfaceContainerHighest,
              child: Icon(Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant),
            ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cookie_outlined, size: 56),
            const SizedBox(height: 12),
            Text('No recipes yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Add a recipe to start costing it.',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
