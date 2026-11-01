import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'blob_store.dart';

/// Stores immutable blob bytes as files in an injected directory.
class FileBlobStore implements BlobStore {
  final Directory _rootDir;

  FileBlobStore(this._rootDir);

  final _available = StreamController<String>.broadcast();

  @override
  Stream<String> get availableBlobs => _available.stream;

  @override
  Future<Uint8List?> get(String blobId) async {
    final file = _file(blobId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> save(String blobId, Uint8List data) async {
    final file = _file(blobId);
    if (await file.exists()) {
      final existing = await file.readAsBytes();
      if (!_bytesEqual(existing, data)) {
        throw StateError('Blob already contains different bytes: $blobId');
      }
      return;
    }

    await _rootDir.create(recursive: true);
    await file.writeAsBytes(data, flush: true);
    _available.add(blobId);
  }

  @override
  Future<List<String>> listIds() async {
    if (!await _rootDir.exists()) return [];
    final ids = <String>[];
    await for (final entity in _rootDir.list(followLinks: false)) {
      if (entity is File) {
        ids.add(entity.uri.pathSegments.last);
      }
    }
    return ids;
  }

  @override
  Future<void> delete(String blobId) async {
    final file = _file(blobId);
    if (await file.exists()) await file.delete();
  }

  File _file(String blobId) =>
      File('${_rootDir.path}${Platform.pathSeparator}$blobId');
}

bool _bytesEqual(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var index = 0; index < first.length; index++) {
    if (first[index] != second[index]) return false;
  }
  return true;
}
