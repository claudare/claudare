import 'dart:io';

import 'package:core/encryption.dart';
import 'package:core/src/blob_store/blob_id.dart';
import 'package:core/src/blob_store/stat.dart';
import 'package:core/src/timestamp.dart';
import 'package:path/path.dart' as path;

// use package:path_provider for basepath for prod
// this is a local blob store, things are saved without encryption
// when replicated to a remote server, encryption is applied
class BlobStore {
  final String _basePath;
  final bool _temporary;

  BlobStore(this._basePath) : _temporary = false;

  BlobStore.temporary() : _basePath = _tempStorageDir(), _temporary = true;

  Future<void> init() async {
    await Directory(_basePath).create(recursive: true);
  }

  Future<void> deinit() async {
    if (_temporary) {
      await _tempStorageCleanup(_basePath);
    }
  }

  Future<bool> has(BlobId id) async {
    final file = _getFile(id);
    return await file.exists();
  }

  // TODO: add progress notification?
  // TODO: seakable start
  // TODO: slow/buffered read
  // all these features need to know the filesizes, but its encrypted
  // so many using crypto bytes
  Stream<List<int>> read(BlobId id, {Encryptor? encryptor}) {
    final file = _getFile(id);

    // technically a "has" could be checked here and null returned
    // but this can create a race condition

    final stream = file.openRead();

    return encryptor != null ? encryptor.decrypt(stream) : stream;
  }

  // TODO: add progress notification
  Future<void> write(
    BlobId id,
    Stream<List<int>> stream, {
    Encryptor? encryptor,
  }) async {
    if (await has(id)) {
      throw Exception('blob overwrite is not allowed');
    }

    final file = _getFile(id);
    // TODO: remove utf8 encoding?
    final sink = file.openWrite(mode: FileMode.writeOnly);

    final outStream = encryptor != null ? encryptor.encrypt(stream) : stream;

    try {
      await sink.addStream(outStream);
      // TODO: does this need a flush?
      await sink.flush();
    } catch (e) {
      rethrow;
    } finally {
      await sink.close();
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

  /// returns a list of all available blobs
  /// WARNING: this is slow, dont use this
  Stream<BlobId> list() {
    final dir = Directory(_basePath);

    return dir
        .list(followLinks: false, recursive: false)
        .where((event) => event is File)
        .map((event) => BlobId(path.basename(event.path)));
  }

  Future<BlobStat?> stat(BlobId id) async {
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

  File _getFile(BlobId id) {
    return File(path.join(_basePath, id.value));
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
