import 'dart:async';

import 'package:blob/src/blob_event.dart';
import 'package:blob/src/blob_store/blob_store.dart';
import 'package:blob/src/path.dart';
import 'package:cqrs/cqrs.dart';

/// Cleanups deleted blobs
final class BlobCleanupProjection implements Projection<Object, BlobEvent> {
  final BlobStore _blobStore;

  @override
  String get name => 'blob-cleanup';

  @override
  LogFilter get filter => LogFilter.startsWith(blobStream(''));

  const BlobCleanupProjection(this._blobStore);

  @override
  FutureOr<ProjectionLoad<Object>> load() => ProjectionLoad.initial(Object());

  @override
  void apply(model, envelope) {
    // noop
    return;
  }

  @override
  Future<void> onStreamDeleted(model, deletion) async {
    final id = blobIdFromStream(deletion.streamPath);
    await _blobStore.delete(id);
  }
}
