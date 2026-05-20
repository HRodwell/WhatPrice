import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../widgets/allergen_chips.dart';
import 'ingredient_edit_screen.dart';

class IngredientsScreen extends StatelessWidget {
  const IngredientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final symbol = state.settings.currencySymbol;
    final items = state.ingredients;

    return Scaffold(
      body: items.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final ing = items[i];
                final price = ing.id == null
                    ? null
                    : state.priceFor(ing.id!);
                return Card(
                  child: ListTile(
                    isThreeLine: ing.allergens.isNotEmpty,
                    title: Text(ing.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (price == null)
                          Text(
                            'No price set for ${state.activePantry.name}',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          )
                        else
                          Text(
                            '${money(price.packCost, symbol)} per ${num2(price.packSize)}${ing.unit.short}'
                            '   ·   ${money(price.unitCost, symbol)}/${ing.unit.short}',
                          ),
                        if (ing.allergens.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          AllergenChipsRow(allergens: ing.allergens, dense: true),
                        ],
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, ing),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, null),
        icon: const Icon(Icons.add),
        label: const Text('New ingredient'),
      ),
    );
  }

  void _open(BuildContext context, Ingredient? ing) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IngredientEditScreen(ingredient: ing)),
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
            const Icon(Icons.egg_outlined, size: 56),
            const SizedBox(height: 12),
            Text('No ingredients yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text('Add flour, butter, eggs… with what you paid.',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
