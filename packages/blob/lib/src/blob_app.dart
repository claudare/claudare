import 'dart:async';
import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_cleanup_projection.dart';
import 'package:blob/src/blob_event.dart';
import 'package:blob/src/path.dart';
import 'package:cqrs/cqrs.dart';

abstract interface class BlobWriter {
  Future<String> save(Uint8List data);
  Future<void> delete(String id);
}

abstract interface class BlobReader {
  Future<Uint8List?> get(String id);
}

class BlobCqrsIntegration implements BlobWriter {
  final CommandContextApi _ctx;
  final BlobStore _blobStore;

  const BlobCqrsIntegration({required this._ctx, required this._blobStore});

  @override
  Future<void> delete(String id) async {
    final stream = _ctx.stream(blobStream(id));
    await stream.delete();
  }

  @override
  Future<String> save(Uint8List data) async {
    final id = _ctx.generateId();

    await _blobStore.save(id, data);

    final stream = _ctx.stream(blobStream(id));
    await stream.mustNotExist();

    stream.append(BlobCreated());
    return id;
  }
}

/// Manages blob commands and erases locally stored bytes after deletion commits.
class BlobApp implements BlobReader {
  final BlobStore _blobStore;
  late final LiveProjection<Object, BlobEvent> _cleanup;

  BlobApp({required CqrsRuntime runtime, required this._blobStore}) {
    runtime.eventRegistry.add(const BlobCreatedCodec());
    _cleanup = runtime.liveProjection(BlobCleanupProjection(_blobStore));
  }

  BlobWriter integrate(CommandContextApi ctx) {
    return BlobCqrsIntegration(ctx: ctx, blobStore: _blobStore);
  }

  @override
  Future<Uint8List?> get(String id) {
    return _blobStore.get(id);
  }

  /// Runs deletion cleanup until stopped or the event source closes.
  Future<void> run() async {
    await _cleanup.latest();
    await _cleanup.done;
  }

  /// Permanently stops cleanup and waits for active work.
  Future<void> stop() async {
    await _cleanup.stop();
  }
}
