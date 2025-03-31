import 'dart:io';

import 'package:core/src/blob_store/id.dart';
import 'package:core/src/blob_store/metadata.dart';
import 'package:core/src/blob_store/stat.dart';
import 'package:core/src/blob_store/stream.dart';
import 'package:core/src/timestamp.dart';
import 'package:path/path.dart' as path;

// use package:path_provider for basepath for prod
// this is a local blob store, things are saved without encryption
// when replicated to a remote server, encryption is applied
class BlobStore {
  final String basePath;
  final bool temporary;

  BlobStore(this.basePath) : temporary = false;

  BlobStore.temporary() : basePath = _tempStorageDir(), temporary = true;

  Future<void> init() async {
    await Directory(basePath).create(recursive: true);
  }

  Future<void> deinit() async {
    if (temporary) {
      await _tempStorageCleanup(basePath);
    }
  }

  Future<bool> has(BlobId id) async {
    final file = _getFile(id);
    return await file.exists();
  }

  Future<BlobStreamWithMetadata?> get(BlobId id) async {
    final file = _getFile(id);

    try {
      final stream = file.openRead();
      return await BlobStreamWithMetadata.fromRawStream(stream);
    } catch (e) {
      print('something went wrong. blob $id could not be loaded: $e');
      // file was not found, but not 100% guarantee...
      return null;
    }
  }

  Future<BlobStat?> getStat(BlobId id) async {
    final file = _getFile(id);

    final fileStat = await file.stat();

    if (fileStat.type == FileSystemEntityType.notFound) {
      return null;
    }

    return BlobStat(
      fileStat.size,
      Timestamp.fromDateTime(fileStat.modified),
      Timestamp.fromDateTime(fileStat.accessed),
    );
  }

  // would be nice to have a progress here... atleast by chunk count
  Future<void> put(
    BlobId id,
    BlobMetadata metadata,
    Stream<List<int>> content,
  ) async {
    // TODO: if file already exist we throw?
    final wrappedStream = BlobStreamWithMetadata.wrapContent(metadata, content);

    final file = _getFile(id);
    final sink = file.openWrite();

    try {
      // TODO: check that written amount is the same as in meta
      await sink.addStream(wrappedStream);
    } catch (e) {
      rethrow;
    } finally {
      sink.close();
    }
  }

  Future<bool> delete(BlobId id) async {
    final file = _getFile(id);
    try {
      await file.delete();
      return true;
    } catch (e) {
      // error wrapping is an issue again... maybe I should rethrow own errors?
      return false;
    }
  }

  Future<List<BlobId>> list() async {
    final dir = Directory(basePath);

    final items =
        await dir
            .list(followLinks: false, recursive: false)
            .where((event) => event.runtimeType == File)
            .map((event) => BlobId(path.basename(event.path)))
            .toList();

    return items;
  }

  File _getFile(BlobId id) {
    return File(path.join(basePath, id.value));
  }
}

String _tempStorageDir() {
  final tempDir = Directory.systemTemp.path;
  return Directory(tempDir).createTempSync('blob_store').path;
}

Future<void> _tempStorageCleanup(String maybeTempDir) async {
  // check that this dir is in Directory.systemTemp.path
  if (!maybeTempDir.startsWith(Directory.systemTemp.path)) {
    throw Exception(
      'Attempted to cleanup storage not in a temporary directory!!!',
    );
  }

  await Directory(maybeTempDir).delete(recursive: true);
}
