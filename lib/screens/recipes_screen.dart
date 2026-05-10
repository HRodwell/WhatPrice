import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cost.dart';
import '../format.dart';
import '../models.dart';
import 'recipe_edit_screen.dart';

class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final recipes = state.recipes;

    return Scaffold(
      body: recipes.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: recipes.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) =>
                  _RecipeCard(recipe: recipes[i], state: state),
            ),
      floatingActionButton: FloatingActionButton.extended(
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

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, required this.state});
  final Recipe recipe;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => RecipesScreen._open(context, recipe),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
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
              const Icon(Icons.chevron_right),
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
    return FutureBuilder<List<RecipeIngredient>>(
      future: state.loadRecipeLines(recipe.id!),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final breakdown = computeCost(
          recipe: recipe,
          lines: snap.data!,
          ingredientsById: state.ingredientsById,
          settings: state.settings,
        );
        final symbol = state.settings.currencySymbol;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(
              label: 'Per piece',
              value: money(breakdown.costPerPiece, symbol),
            ),
            _Chip(
              label: 'Suggested',
              value: money(breakdown.suggestedPricePerPiece, symbol),
              tone: Theme.of(context).colorScheme.primaryContainer,
            ),
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
