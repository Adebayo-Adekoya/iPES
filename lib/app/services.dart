/// Platform services: picking and saving files, and local persistence.
/// Kept behind small interfaces so widget tests can use fakes.
library;

import 'dart:io' show File;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/cataloguer.dart';
import '../core/library.dart';

abstract class FileService {
  /// Lets the user choose files to import. Empty when cancelled.
  Future<List<ImportedFile>> pickFiles();

  /// Saves [bytes] where the user chooses (a download on the web).
  /// Returns a description of where it went, or null when cancelled.
  Future<String?> saveFile(String fileName, Uint8List bytes, String mimeType);
}

class PlatformFileService implements FileService {
  @override
  Future<List<ImportedFile>> pickFiles() async {
    final picked = await FilePicker.pickFiles(dialogTitle: 'Add to iPES');
    final out = <ImportedFile>[];
    for (final f in picked) {
      out.add(ImportedFile(f.name, await f.readAsBytes()));
    }
    return out;
  }

  @override
  Future<String?> saveFile(String fileName, Uint8List bytes, String mimeType) async {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
    if (kIsWeb) return 'Downloaded $fileName';
    return uri == null ? null : 'Saved $fileName';
  }
}

/// Stores the catalogue as one JSON file in the app's private documents
/// folder. (The full product uses encrypted SQLite; see spec section 4.)
class FileStorage implements LibraryStorage {
  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ipes_library.json');
  }

  @override
  Future<String?> load() async {
    final f = await _file();
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> save(String json) async {
    final f = await _file();
    await f.writeAsString(json, flush: true);
  }
}

LibraryStorage defaultStorage() => kIsWeb ? MemoryStorage() : FileStorage();
