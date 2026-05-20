class SyncField {
  final String name;
  final SyncFieldType type;
  final bool nullable;
  const SyncField(this.name, this.type, {this.nullable = false});
}

enum SyncFieldType { text, int_, real, bool_ }

class SyncFkField {
  final String localCol;
  final String remoteCol;
  final String refTable;
  const SyncFkField({
    required this.localCol,
    required this.remoteCol,
    required this.refTable,
  });
}

class SyncFileField {
  final String localPathCol;
  final String remoteFileCol;
  const SyncFileField({
    required this.localPathCol,
    required this.remoteFileCol,
  });
}

class SyncCollection {
  final String localTable;
  final String remoteName;
  final List<SyncField> fields;
  final List<SyncFkField> fkFields;
  final List<SyncFileField> fileFields;
  /// True if this table has no single `id` primary-key column (composite PK).
  final bool noLocalId;

  const SyncCollection({
    required this.localTable,
    required this.remoteName,
    required this.fields,
    this.fkFields = const [],
    this.fileFields = const [],
    this.noLocalId = false,
  });
}

const syncCollections = <SyncCollection>[
  SyncCollection(
    localTable: 'pantries',
    remoteName: 'pantries',
    fields: [
      SyncField('name', SyncFieldType.text),
    ],
  ),
  SyncCollection(
    localTable: 'ingredients',
    remoteName: 'ingredients',
    fields: [
      SyncField('name', SyncFieldType.text),
      SyncField('unit', SyncFieldType.text),
      SyncField('allergen_flags', SyncFieldType.int_),
    ],
  ),
  SyncCollection(
    localTable: 'ingredient_prices',
    remoteName: 'ingredient_prices',
    fields: [
      SyncField('pack_size', SyncFieldType.real),
      SyncField('pack_cost', SyncFieldType.real),
    ],
    fkFields: [
      SyncFkField(
        localCol: 'ingredient_id',
        remoteCol: 'ingredient_sync_id',
        refTable: 'ingredients',
      ),
      SyncFkField(
        localCol: 'pantry_id',
        remoteCol: 'pantry_sync_id',
        refTable: 'pantries',
      ),
    ],
  ),
  SyncCollection(
    localTable: 'recipes',
    remoteName: 'recipes',
    fields: [
      SyncField('name', SyncFieldType.text),
      SyncField('yield_pieces', SyncFieldType.int_),
      SyncField('oven_minutes', SyncFieldType.real),
      SyncField('labour_minutes', SyncFieldType.real),
      SyncField('notes', SyncFieldType.text, nullable: true),
    ],
  ),
  SyncCollection(
    localTable: 'recipe_ingredients',
    remoteName: 'recipe_ingredients',
    fields: [
      SyncField('quantity', SyncFieldType.real),
    ],
    fkFields: [
      SyncFkField(
        localCol: 'recipe_id',
        remoteCol: 'recipe_sync_id',
        refTable: 'recipes',
      ),
      SyncFkField(
        localCol: 'ingredient_id',
        remoteCol: 'ingredient_sync_id',
        refTable: 'ingredients',
      ),
    ],
  ),
  SyncCollection(
    localTable: 'recipe_images',
    remoteName: 'recipe_images',
    fields: [
      SyncField('sort_order', SyncFieldType.int_),
    ],
    fkFields: [
      SyncFkField(
        localCol: 'recipe_id',
        remoteCol: 'recipe_sync_id',
        refTable: 'recipes',
      ),
    ],
    fileFields: [
      SyncFileField(localPathCol: 'path', remoteFileCol: 'image'),
    ],
  ),
  SyncCollection(
    localTable: 'recipe_cost_snapshots',
    remoteName: 'recipe_cost_snapshots',
    fields: [
      SyncField('margin_percent', SyncFieldType.real),
      SyncField('include_labour', SyncFieldType.int_),
      SyncField('ingredients_cost', SyncFieldType.real),
      SyncField('energy_cost', SyncFieldType.real),
      SyncField('labour_cost', SyncFieldType.real),
      SyncField('cost_per_piece', SyncFieldType.real),
      SyncField('suggested_price_per_piece', SyncFieldType.real),
      SyncField('suggested_batch_price', SyncFieldType.real),
      SyncField('computed_at', SyncFieldType.text),
    ],
    fkFields: [
      SyncFkField(
        localCol: 'recipe_id',
        remoteCol: 'recipe_sync_id',
        refTable: 'recipes',
      ),
      SyncFkField(
        localCol: 'pantry_id',
        remoteCol: 'pantry_sync_id',
        refTable: 'pantries',
      ),
    ],
    noLocalId: true,
  ),
  SyncCollection(
    localTable: 'productions',
    remoteName: 'productions',
    fields: [
      SyncField('made_at', SyncFieldType.text),
      SyncField('batches', SyncFieldType.int_),
      SyncField('cost_per_piece', SyncFieldType.real, nullable: true),
      SyncField('notes', SyncFieldType.text, nullable: true),
    ],
    fkFields: [
      SyncFkField(
        localCol: 'recipe_id',
        remoteCol: 'recipe_sync_id',
        refTable: 'recipes',
      ),
      SyncFkField(
        localCol: 'pantry_id',
        remoteCol: 'pantry_sync_id',
        refTable: 'pantries',
      ),
    ],
  ),
];
