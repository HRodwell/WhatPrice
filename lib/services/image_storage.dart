import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ImageStorage {
  ImageStorage._();
  static final ImageStorage instance = ImageStorage._();

  static const _dirName = 'whatprice_images';
  static const _uuid = Uuid();
  final _imagePicker = ImagePicker();

  Future<Directory> _imagesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  File resolve(String relativePath, Directory imagesDir) =>
      File(p.join(imagesDir.path, relativePath));

  Future<File> resolveAsync(String relativePath) async {
    final dir = await _imagesDir();
    return resolve(relativePath, dir);
  }

  Future<Directory> ensureDir() => _imagesDir();

  Future<List<File>> pickSources({required bool useCamera}) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final picked = useCamera
          ? <XFile?>[await _imagePicker.pickImage(source: ImageSource.camera)]
          : await _imagePicker.pickMultiImage();
      return picked.whereType<XFile>().map((x) => File(x.path)).toList();
    } else {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.image,
      );
      if (result == null) return const [];
      return result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
    }
  }

  Future<List<String>> storeAll(Iterable<File> sources) async {
    final dir = await _imagesDir();
    final out = <String>[];
    for (final src in sources) {
      final ext = p.extension(src.path).toLowerCase();
      final name = '${_uuid.v4()}${ext.isEmpty ? '.jpg' : ext}';
      final dest = File(p.join(dir.path, name));
      await src.copy(dest.path);
      out.add(name);
    }
    return out;
  }

  Future<List<String>> pickAndStore({required bool useCamera}) async {
    final sources = await pickSources(useCamera: useCamera);
    return storeAll(sources);
  }

  Future<void> delete(String relativePath) async {
    final f = await resolveAsync(relativePath);
    if (await f.exists()) {
      await f.delete();
    }
  }
}
