import 'package:flutter/material.dart';

import '../allergens.dart';

class AllergenChipsRow extends StatelessWidget {
  const AllergenChipsRow({
    super.key,
    required this.allergens,
    this.dense = false,
  });

  final AllergenSet allergens;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (allergens.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: dense ? 4 : 6,
      runSpacing: dense ? 4 : 6,
      children: [
        for (final a in allergens.values)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 6 : 8,
              vertical: dense ? 2 : 4,
            ),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              a.label,
              style: TextStyle(
                fontSize: dense ? 10 : 12,
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

class AllergenSelector extends StatelessWidget {
  const AllergenSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final AllergenSet value;
  final ValueChanged<AllergenSet> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in Allergen.values)
          FilterChip(
            label: Text(a.label),
            selected: value.contains(a),
            onSelected: (_) => onChanged(value.toggle(a)),
          ),
      ],
    );
  }
}
