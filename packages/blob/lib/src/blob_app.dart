import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
import 'package:blob/src/blobs_aggregate.dart';
import 'package:blob/src/path.dart';
import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';

abstract interface class BlobWriter {
  Future<String> save(CommandContextApi ctx, Uint8List data);
  Future<void> delete(CommandContextApi ctx, String id);
}

abstract interface class BlobReader {
  Future<Uint8List?> get(String id);
}

class BlobApp implements BlobReader, BlobWriter {
  final CqrsRuntime _runtime;
  final BlobStore _blobStore;
  final IdGenerator _idGenerator;

  BlobApp({
    required this._runtime,
    required this._blobStore,
    IdGenerator? idGenerator,
  }) : _idGenerator = idGenerator ?? IdGeneratorRandom() {
    _runtime.eventRegistry.add(const BlobCreatedCodec());
  }

  @override
  Future<Uint8List?> get(String id) {
    return _blobStore.get(id);
  }

  @override
  Future<void> delete(CommandContextApi ctx, String id) async {
    final stream = ctx.stream(blobStream(id));
    await stream.delete();
  }

  @override
  Future<String> save(CommandContextApi ctx, Uint8List data) async {
    final id = _idGenerator.generateId();

    await _blobStore.save(id, data);

    final stream = ctx.stream(blobStream(id));
    await stream.mustNotExist();

    stream.append(BlobCreated());
    return id;
  }

  /// Deletes unreferenced local blobs. The runtime must be idle while this runs.
  Future<void> optimize() async {
    final storedIds = (await _blobStore.listIds()).toSet();
    final blobs = await _runtime.resolve(blobsAggregate());
    final unused = storedIds.difference(blobs.state.activeIds);

    for (final id in unused) {
      await _blobStore.delete(id);
    }
  }
}
