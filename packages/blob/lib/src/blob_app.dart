import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
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

    final stream = ctx.stream('_blob/$id');
    await stream.mustNotExist();

    stream.append(BlobCreated());
    return id;
  }
}
