import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models.dart';
import 'pdf_export.dart';

class BulkExportResult {
  final bool ok;
  final String? savedPath;
  final String? message;
  const BulkExportResult.shared({this.savedPath})
      : ok = true,
        message = null;
  const BulkExportResult.saved(String path)
      : ok = true,
        savedPath = path,
        message = null;
  const BulkExportResult.cancelled()
      : ok = false,
        savedPath = null,
        message = null;
  const BulkExportResult.error(this.message)
      : ok = false,
        savedPath = null;
}

Future<BulkExportResult> exportRecipesAsZip({
  required List<Recipe> recipes,
  required AppState state,
}) async {
  if (recipes.isEmpty) return const BulkExportResult.cancelled();

  final archive = Archive();
  final usedNames = <String>{};

  final pantry = state.activePantry;
  final prices = state.pricesForPantry(state.activePantryId);

  for (final recipe in recipes) {
    final lines = await state.loadRecipeLines(recipe.id!);
    final images = await state.loadRecipeImages(recipe.id!);
    final snapshot = state.snapshotOf(recipe.id!);
    final bytes = await buildRecipePdf(RecipePdfInput(
      recipe: recipe,
      lines: lines,
      images: images,
      ingredientsById: state.ingredientsById,
      pricesByIngredientId: prices,
      settings: state.settings,
      pantryName: pantry.name,
      snapshot: snapshot,
    ));
    final filename = _uniqueName(recipe.name, usedNames);
    archive.addFile(ArchiveFile(filename, bytes.length, bytes));
  }

  final zipBytes = ZipEncoder().encode(archive);
  if (zipBytes == null) {
    return const BulkExportResult.error('Failed to build zip');
  }
  final zipFilename = _zipFilename();

  if (Platform.isAndroid || Platform.isIOS) {
    final tmp = await getTemporaryDirectory();
    final path = p.join(tmp.path, zipFilename);
    await File(path).writeAsBytes(zipBytes, flush: true);
    final result = await Share.shareXFiles(
      [XFile(path, mimeType: 'application/zip')],
      subject: zipFilename,
    );
    if (result.status == ShareResultStatus.dismissed) {
      return const BulkExportResult.cancelled();
    }
    return BulkExportResult.shared(savedPath: path);
  } else {
    final outPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save recipes archive',
      fileName: zipFilename,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      bytes: Uint8List.fromList(zipBytes),
    );
    if (outPath == null) return const BulkExportResult.cancelled();
    final f = File(outPath);
    if (!await f.exists() || await f.length() == 0) {
      await f.writeAsBytes(zipBytes, flush: true);
    }
    return BulkExportResult.saved(outPath);
  }
}

String _zipFilename() {
  final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now());
  return 'recipes-$stamp.zip';
}

String _uniqueName(String recipeName, Set<String> used) {
  var base = recipeName
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
  if (base.isEmpty) base = 'recipe';
  var name = '$base.pdf';
  var i = 2;
  while (used.contains(name)) {
    name = '${base}_$i.pdf';
    i++;
  }
  used.add(name);
  return name;
}
