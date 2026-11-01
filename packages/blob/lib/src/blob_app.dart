import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
import 'package:blob/src/path.dart';
import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';

abstract interface class BlobWriter {
  Future<String> save(CommandContextApi ctx, Uint8List data);
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
    final unused = (await _blobStore.listIds()).toSet();
    final events = _runtime.logReader(LogFilter.startsWith(blobStream('')), 0);
    await for (final event in events.scan()) {
      final decoded = _runtime.eventRegistry.decode<BlobEvent>(
        event.encodedEvent,
      );
      if (decoded is BlobCreated) {
        unused.remove(blobIdFromStream(event.streamPath));
      }
    }

    for (final id in unused) {
      await _blobStore.delete(id);
    }
  }
}
