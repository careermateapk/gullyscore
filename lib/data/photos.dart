// Player photos. They are copied into the app's own folder on this phone
// and never uploaded anywhere.
import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class PhotoStore {
  static String? _dir;

  /// Finds the photo folder. Safe to call more than once.
  static Future<void> init() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final d = Directory('${docs.path}/player_photos');
      if (!await d.exists()) await d.create(recursive: true);
      _dir = d.path;
    } catch (_) {
      _dir = null; // photos simply won't show
    }
  }

  /// The picture file for [fileName], or null when it is missing.
  static File? file(String? fileName) {
    final d = _dir;
    if (d == null || fileName == null) return null;
    final f = File('$d/$fileName');
    return f.existsSync() ? f : null;
  }

  /// Lets the user take or choose a picture; returns its temporary path,
  /// or null if they backed out. Cropping happens afterwards.
  static Future<String?> pickRaw({required bool camera}) async {
    final x = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
      preferredCameraDevice: CameraDevice.rear,
    );
    return x?.path;
  }

  /// Saves cropped picture bytes; returns the new file name.
  static Future<String> saveBytes(String prefix, Uint8List bytes) async {
    if (_dir == null) await init();
    final d = _dir;
    if (d == null) throw StateError('no photo folder');
    final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File('$d/$name').writeAsBytes(bytes, flush: true);
    return name;
  }

  /// Folder path, for backups.
  static String? get dir => _dir;

  static Future<void> delete(String fileName) async {
    try {
      file(fileName)?.deleteSync();
    } catch (_) {}
  }

  static Future<void> deleteAll() async {
    final d = _dir;
    if (d == null) return;
    try {
      final dir = Directory(d);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
      }
    } catch (_) {}
  }
}
