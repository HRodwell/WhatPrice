import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cost.dart';
import '../format.dart';
import '../models.dart';
import '../services/image_storage.dart';
import '../widgets/allergen_chips.dart';
import '../widgets/production_section.dart';

class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key, this.recipe});
  final Recipe? recipe;

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _yield;
  late final TextEditingController _oven;
  late final TextEditingController _labour;
  late final TextEditingController _notes;

  List<RecipeIngredient> _lines = [];
  final List<_ImageEntry> _imageEntries = [];
  final List<RecipeImage> _imagesToDelete = [];
  Directory? _imagesDir;
  final PageController _carousel = PageController();
  int _carouselIndex = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    _name = TextEditingController(text: r?.name ?? '');
    _yield = TextEditingController(text: r == null ? '12' : '${r.yieldPieces}');
    _oven = TextEditingController(text: r == null ? '15' : num2(r.ovenMinutes));
    _labour = TextEditingController(
        text: r == null ? '20' : num2(r.labourMinutes));
    _notes = TextEditingController(text: r?.notes ?? '');
    _loadLines();
  }

  Future<void> _loadLines() async {
    final r = widget.recipe;
    final state = context.read<AppState>();
    _imagesDir = await ImageStorage.instance.ensureDir();
    if (r?.id != null) {
      _lines = await state.loadRecipeLines(r!.id!);
      final imgs = await state.loadRecipeImages(r.id!);
      _imageEntries.addAll(imgs.map(_ImageEntry.persisted));
    }
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    _yield.dispose();
    _oven.dispose();
    _labour.dispose();
    _notes.dispose();
    _carousel.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final recipe = Recipe(
      id: widget.recipe?.id,
      name: _name.text.trim(),
      yieldPieces: int.parse(_yield.text),
      ovenMinutes: double.parse(_oven.text),
      labourMinutes: double.parse(_labour.text),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final id = await state.upsertRecipe(recipe);
    await state.replaceRecipeLines(id, _lines);
    for (final img in _imagesToDelete) {
      await state.removeRecipeImage(img);
    }
    final pendingSources = _imageEntries
        .where((e) => e.source != null)
        .map((e) => e.source!)
        .toList();
    if (pendingSources.isNotEmpty) {
      final paths = await ImageStorage.instance.storeAll(pendingSources);
      await state.addRecipeImages(id, paths);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = widget.recipe?.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete recipe?'),
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
    final navigator = Navigator.of(context);
    await context.read<AppState>().deleteRecipe(id);
    navigator.pop();
  }

  Future<void> _pickImages({required bool camera}) async {
    final sources =
        await ImageStorage.instance.pickSources(useCamera: camera);
    if (sources.isEmpty) return;
    setState(() {
      for (final f in sources) {
        _imageEntries.add(_ImageEntry.pending(f));
      }
      _carouselIndex = _imageEntries.length - 1;
    });
    if (_carousel.hasClients) {
      _carousel.jumpToPage(_carouselIndex);
    }
  }

  void _removeCurrentImage() {
    if (_imageEntries.isEmpty) return;
    final i = _carouselIndex.clamp(0, _imageEntries.length - 1);
    final entry = _imageEntries[i];
    setState(() {
      if (entry.persisted != null) {
        _imagesToDelete.add(entry.persisted!);
      }
      _imageEntries.removeAt(i);
      if (_imageEntries.isEmpty) {
        _carouselIndex = 0;
      } else if (_carouselIndex >= _imageEntries.length) {
        _carouselIndex = _imageEntries.length - 1;
      }
    });
    if (_imageEntries.isNotEmpty && _carousel.hasClients) {
      _carousel.jumpToPage(_carouselIndex);
    }
  }

  Future<void> _addOrEditLine([RecipeIngredient? existing]) async {
    final state = context.read<AppState>();
    if (state.ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add ingredients first.')),
      );
      return;
    }
    final result = await showModalBottomSheet<RecipeIngredient>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _IngredientLineSheet(
        ingredients: state.ingredients,
        existing: existing,
      ),
    );
    if (result == null) return;
    setState(() {
      if (existing != null) {
        final i = _lines.indexOf(existing);
        if (i >= 0) _lines[i] = result;
      } else {
        _lines.add(result);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isNew = widget.recipe == null;
    final symbol = state.settings.currencySymbol;
    final snapshot = widget.recipe?.id == null
        ? null
        : state.snapshotOf(widget.recipe!.id!);
    final pantryName = state.activePantry.name;

    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New recipe' : 'Edit recipe'),
        actions: [
          if (!isNew)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              onChanged: () => setState(() {}),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _ImageCarousel(
                    entries: _imageEntries,
                    imagesDir: _imagesDir,
                    controller: _carousel,
                    currentIndex: _carouselIndex,
                    onPageChanged: (i) =>
                        setState(() => _carouselIndex = i),
                    onAdd: () => _pickImages(camera: false),
                    onCapture: (Platform.isAndroid || Platform.isIOS)
                        ? () => _pickImages(camera: true)
                        : null,
                    onRemove: _removeCurrentImage,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Recipe name'),
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _yield,
                        decoration: const InputDecoration(
                            labelText: 'Yield (pieces)'),
                        keyboardType: TextInputType.number,
                        validator: _positiveInt,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _oven,
                        decoration: const InputDecoration(
                            labelText: 'Bake time (min)'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: _nonNegative,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _labour,
                    decoration: const InputDecoration(
                      labelText: 'Labour time (min)',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _nonNegative,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 2,
                  ),
                  if (_loaded) ...[
                    Builder(builder: (_) {
                      final allergens = allergensFor(
                        _lines,
                        state.ingredientsById,
                      );
                      if (allergens.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contains',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 6),
                            AllergenChipsRow(allergens: allergens),
                          ],
                        ),
                      );
                    }),
                  ],
                  const SizedBox(height: 24),
                  _SectionHeader(
                    title: 'Ingredients',
                    trailing: TextButton.icon(
                      onPressed: () => _addOrEditLine(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ),
                  if (_lines.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'No ingredients added.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  else
                    ..._lines.map((line) {
                      final ing = state.ingredientsById[line.ingredientId];
                      final price = state.priceFor(line.ingredientId);
                      final cost = (price?.unitCost ?? 0) * line.quantity;
                      final missing = price == null && ing != null;
                      return Card(
                        child: ListTile(
                          title: Text(ing?.name ?? 'Unknown'),
                          subtitle: Text(
                            missing
                                ? '${num2(line.quantity)} ${ing.unit.short}   ·   No price in ${state.activePantry.name}'
                                : '${num2(line.quantity)} ${ing?.unit.short ?? ''}   ·   ${money(cost, symbol)}',
                            style: missing
                                ? TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  )
                                : null,
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _lines.remove(line)),
                          ),
                          onTap: () => _addOrEditLine(line),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  _CostSummary(
                    snapshot: snapshot,
                    symbol: symbol,
                    pantryName: pantryName,
                  ),
                  if (widget.recipe?.id != null) ...[
                    const SizedBox(height: 24),
                    ProductionSection(recipeId: widget.recipe!.id!),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _loaded ? _save : null,
            icon: const Icon(Icons.check),
            label: const Text('Save recipe'),
          ),
        ),
      ),
    );
  }

  String? _positiveInt(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = int.tryParse(v);
    if (n == null || n <= 0) return '> 0';
    return null;
  }

  String? _nonNegative(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';
    final n = double.tryParse(v);
    if (n == null || n < 0) return '≥ 0';
    return null;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _CostSummary extends StatelessWidget {
  const _CostSummary({
    required this.snapshot,
    required this.symbol,
    required this.pantryName,
  });
  final RecipeCostSnapshot? snapshot;
  final String symbol;
  final String pantryName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (snapshot == null) {
      return Card(
        color: scheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.calculate_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Not calculated for $pantryName — open the Calculate tab to set a price.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final s = snapshot!;
    return Card(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cost breakdown ($pantryName)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Saved ${DateFormat.yMd().add_jm().format(s.computedAt)}'
              '${s.includeLabour ? '' : '   ·   labour excluded'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _row('Ingredients', s.ingredientsCost, symbol),
            _row('Energy', s.energyCost, symbol),
            if (s.labourCost > 0) _row('Labour', s.labourCost, symbol),
            const Divider(height: 24),
            _row('Total batch', s.totalCost, symbol, bold: true),
            _row('Per piece', s.costPerPiece, symbol, bold: true),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_offer_outlined,
                      color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggested price (${num2(s.marginPercent)}% margin)',
                          style: TextStyle(color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${money(s.suggestedPricePerPiece, symbol)} per piece   ·   ${money(s.suggestedBatchPrice, symbol)} per batch',
                          style: TextStyle(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, double v, String s, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: bold ? 15 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(money(v, s), style: style),
        ],
      ),
    );
  }
}

class _IngredientLineSheet extends StatefulWidget {
  const _IngredientLineSheet({required this.ingredients, this.existing});
  final List<Ingredient> ingredients;
  final RecipeIngredient? existing;

  @override
  State<_IngredientLineSheet> createState() => _IngredientLineSheetState();
}

class _IngredientLineSheetState extends State<_IngredientLineSheet> {
  late int _ingredientId;
  late TextEditingController _qty;

  @override
  void initState() {
    super.initState();
    _ingredientId = widget.existing?.ingredientId ?? widget.ingredients.first.id!;
    _qty = TextEditingController(
      text: widget.existing == null ? '' : num2(widget.existing!.quantity),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.ingredients.firstWhere(
      (i) => i.id == _ingredientId,
      orElse: () => widget.ingredients.first,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'Add ingredient' : 'Edit ingredient',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _ingredientId,
            decoration: const InputDecoration(labelText: 'Ingredient'),
            isExpanded: true,
            items: widget.ingredients
                .map((i) => DropdownMenuItem(
                      value: i.id,
                      child: Text(i.name, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _ingredientId = v ?? _ingredientId),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            autofocus: widget.existing == null,
            decoration: InputDecoration(
              labelText: 'Quantity',
              suffixText: selected.unit.short,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('OK'),
            onPressed: () {
              final q = double.tryParse(_qty.text);
              if (q == null || q <= 0) return;
              Navigator.of(context).pop(RecipeIngredient(
                id: widget.existing?.id,
                recipeId: widget.existing?.recipeId ?? 0,
                ingredientId: _ingredientId,
                quantity: q,
              ));
            },
          ),
        ],
      ),
    );
  }
}

class _ImageEntry {
  final RecipeImage? persisted;
  final File? source;
  const _ImageEntry._(this.persisted, this.source);
  factory _ImageEntry.persisted(RecipeImage img) => _ImageEntry._(img, null);
  factory _ImageEntry.pending(File file) => _ImageEntry._(null, file);
}

class _ImageCarousel extends StatelessWidget {
  const _ImageCarousel({
    required this.entries,
    required this.imagesDir,
    required this.controller,
    required this.currentIndex,
    required this.onPageChanged,
    required this.onAdd,
    required this.onRemove,
    this.onCapture,
  });

  final List<_ImageEntry> entries;
  final Directory? imagesDir;
  final PageController controller;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback? onCapture;

  File? _resolve(_ImageEntry entry) {
    if (entry.source != null) return entry.source;
    if (imagesDir == null) return null;
    return ImageStorage.instance.resolve(entry.persisted!.path, imagesDir!);
  }

  void _openViewer(BuildContext context, int initialIndex) {
    final files = entries.map(_resolve).whereType<File>().toList();
    if (files.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, __, ___) =>
            _FullscreenViewer(files: files, initialIndex: initialIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 220,
        color: scheme.surfaceContainerHighest,
        child: entries.isEmpty
            ? _EmptyState(onAdd: onAdd, onCapture: onCapture)
            : Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: controller,
                    onPageChanged: onPageChanged,
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      final file = entry.source ??
                          (imagesDir == null
                              ? null
                              : ImageStorage.instance
                                  .resolve(entry.persisted!.path, imagesDir!));
                      if (file == null) {
                        return const SizedBox.shrink();
                      }
                      return GestureDetector(
                        onTap: () => _openViewer(context, i),
                        child: Image.file(file, fit: BoxFit.cover),
                      );
                    },
                  ),
                  if (entries.length > 1)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(entries.length, (i) {
                          final selected = i == currentIndex;
                          return Container(
                            width: selected ? 10 : 6,
                            height: selected ? 10 : 6,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(
                                  alpha: selected ? 0.95 : 0.55),
                            ),
                          );
                        }),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _RoundIconButton(
                      icon: Icons.close,
                      tooltip: 'Remove image',
                      onPressed: onRemove,
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Row(
                      children: [
                        if (onCapture != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _RoundIconButton(
                              icon: Icons.photo_camera_outlined,
                              tooltip: 'Take photo',
                              onPressed: onCapture!,
                            ),
                          ),
                        _RoundIconButton(
                          icon: Icons.add_photo_alternate_outlined,
                          tooltip: 'Add images',
                          onPressed: onAdd,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, this.onCapture});
  final VoidCallback onAdd;
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onAdd,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_photo_alternate_outlined, size: 36),
            const SizedBox(height: 8),
            const Text('Tap to add photos'),
            if (onCapture != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onCapture,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take a photo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FullscreenViewer extends StatefulWidget {
  const _FullscreenViewer({required this.files, required this.initialIndex});
  final List<File> files;
  final int initialIndex;

  @override
  State<_FullscreenViewer> createState() => _FullscreenViewerState();
}

class _FullscreenViewerState extends State<_FullscreenViewer> {
  late final PageController _page = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _page,
            itemCount: widget.files.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.file(widget.files[i], fit: BoxFit.contain),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: _RoundIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (widget.files.length > 1)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_index + 1} / ${widget.files.length}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}
