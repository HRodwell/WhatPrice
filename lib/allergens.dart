enum Allergen {
  gluten(1 << 0, 'Gluten'),
  dairy(1 << 1, 'Dairy'),
  egg(1 << 2, 'Egg'),
  soy(1 << 3, 'Soy'),
  peanut(1 << 4, 'Peanut'),
  treeNut(1 << 5, 'Tree nut'),
  sesame(1 << 6, 'Sesame'),
  sulphite(1 << 7, 'Sulphite'),
  fish(1 << 8, 'Fish'),
  crustacean(1 << 9, 'Crustacean'),
  mollusc(1 << 10, 'Mollusc'),
  celery(1 << 11, 'Celery'),
  mustard(1 << 12, 'Mustard'),
  lupin(1 << 13, 'Lupin');

  const Allergen(this.flag, this.label);
  final int flag;
  final String label;
}

class AllergenSet {
  const AllergenSet(this.mask);
  final int mask;

  static const empty = AllergenSet(0);

  bool contains(Allergen a) => (mask & a.flag) != 0;
  bool get isEmpty => mask == 0;
  bool get isNotEmpty => mask != 0;

  AllergenSet add(Allergen a) => AllergenSet(mask | a.flag);
  AllergenSet remove(Allergen a) => AllergenSet(mask & ~a.flag);
  AllergenSet toggle(Allergen a) =>
      contains(a) ? remove(a) : add(a);
  AllergenSet union(AllergenSet other) => AllergenSet(mask | other.mask);

  Iterable<Allergen> get values =>
      Allergen.values.where((a) => (mask & a.flag) != 0);

  @override
  bool operator ==(Object other) => other is AllergenSet && other.mask == mask;

  @override
  int get hashCode => mask.hashCode;
}

