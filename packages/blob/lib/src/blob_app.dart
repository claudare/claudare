import 'dart:async';
import 'dart:typed_data';

import 'package:blob/blob.dart';
import 'package:blob/src/blob_event.dart';
import 'package:blob/src/blobs_projection.dart';
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

/// Manages blob commands and erases locally stored bytes after deletion commits.
class BlobApp implements BlobReader, BlobWriter {
  final CqrsRuntime _runtime;
  final BlobStore _blobStore;
  final IdGenerator _idGenerator;
  StreamIterator<void>? _changes;
  Future<void>? _running;
  bool _closed = false;

  BlobApp({
    required this._runtime,
    required this._blobStore,
    IdGenerator? idGenerator,
  }) : _idGenerator = idGenerator ?? IdGeneratorRandom() {
    _runtime.eventRegistry.add(const BlobCreatedCodec());
  }

  /// Starts once, processing existing and future committed blob deletions.
  /// Completes when [close] stops it, or fails with a read or deletion error.
  Future<void> run() {
    if (_running != null) throw StateError('BlobApp already started');
    final filter = LogFilter.startsWith(blobStream(''));
    final changes = StreamIterator<void>(
      Stream<void>.multi((controller) {
        final subscription = _runtime.logPlayer
            .subscribe(filter)
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
        controller.onCancel = subscription.cancel;
        // Subscribe before the initial scan so concurrent commits are observed.
        controller.add(null);
      }),
    );
    _changes = changes;
    return _running = _eraseDeletedBlobs(filter, changes);
  }

  Future<void> _eraseDeletedBlobs(
    LogFilter filter,
    StreamIterator<void> changes,
  ) async {
    var fromPosition = 0;
    try {
      while (await changes.moveNext()) {
        if (_closed) return;
        final events = _runtime.logPlayer.logReader(
          filter,
          fromPosition: fromPosition,
        );
        await for (final event in events) {
          if (_closed) return;
          if (event.encodedEvent.isStreamDeleted) {
            await _blobStore.delete(blobIdFromStream(event.streamPath));
          }
          fromPosition = event.position + 1;
        }
      }
    } finally {
      await changes.cancel();
    }
  }

  /// Stops listening and waits for an active deletion. Propagates [run] errors.
  Future<void> close() async {
    final running = _running;
    if (running == null) throw StateError('BlobApp has not started');
    _closed = true;
    await _changes!.cancel();
    await running;
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
    final blobs = await _runtime.resolveProjection(BlobsProjection());
    final unused = storedIds.difference(blobs.activeIds);

    for (final id in unused) {
      await _blobStore.delete(id);
    }
  }
}
