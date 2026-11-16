import 'dart:async';

import 'package:blob/src/blob_event.dart';
import 'package:blob/src/path.dart';
import 'package:cqrs/cqrs.dart';

/// Tracks active and permanently deleted blob stream IDs.
final class BlobIndexProjection
    implements Projection<BlobIndexModel, BlobEvent> {
  @override
  String get name => 'blob-index';

  @override
  LogFilter get filter => LogFilter.startsWith(blobStream(''));

  @override
  FutureOr<ProjectionLoad<BlobIndexModel>> load() =>
      ProjectionLoad.initial(BlobIndexModel._());

  @override
  void apply(model, envelope) {
    if (envelope.event is BlobCreated) {
      model.activeIds.add(blobIdFromStream(envelope.streamPath));
    }
  }

  @override
  void onStreamDeleted(model, deletion) {
    final id = blobIdFromStream(deletion.streamPath);
    model.activeIds.remove(id);
    model.deletedIds.add(id);
  }
}

/// Active and permanently deleted blob identifiers.
class BlobIndexModel {
  final Set<String> activeIds = {};
  final Set<String> deletedIds = {};

  BlobIndexModel._();
}
