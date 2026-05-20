import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models.dart';
import 'calculate_screen.dart';
import 'ingredients_screen.dart';
import 'recipes_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = [
    RecipesScreen(),
    CalculateScreen(),
    IngredientsScreen(),
    SettingsScreen(),
  ];

  static const _titles = ['Recipes', 'Calculate', 'Ingredients', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pantries = state.pantries;
    final active = state.activePantry;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        centerTitle: false,
        actions: [
          if (pantries.length > 1)
            PantrySwitcher(pantries: pantries, active: active)
          else if (pantries.length == 1)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  active.name,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            ),
        ],
      ),
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.cookie_outlined),
            selectedIcon: Icon(Icons.cookie),
            label: 'Recipes',
          ),
          NavigationDestination(
            icon: Icon(Icons.calculate_outlined),
            selectedIcon: Icon(Icons.calculate),
            label: 'Calculate',
          ),
          NavigationDestination(
            icon: Icon(Icons.egg_outlined),
            selectedIcon: Icon(Icons.egg),
            label: 'Ingredients',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class PantrySwitcher extends StatelessWidget {
  const PantrySwitcher({
    super.key,
    required this.pantries,
    required this.active,
  });

  final List<Pantry> pantries;
  final Pantry active;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Switch pantry',
      onSelected: (id) => context.read<AppState>().setActivePantry(id),
      itemBuilder: (_) => [
        for (final p in pantries)
          PopupMenuItem<int>(
            value: p.id,
            child: Row(
              children: [
                Icon(
                  p.id == active.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(p.name),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.kitchen_outlined, size: 18),
            const SizedBox(width: 6),
            Text(
              active.name,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
