import 'dart:async';

import 'package:blob/src/blob_event.dart';
import 'package:blob/src/path.dart';
import 'package:cqrs/cqrs.dart';

/// Tracks active and permanently deleted blob stream IDs.
final class BlobsProjection implements Projection<BlobsModel, BlobEvent> {
  @override
  String get name => 'blobs-status';

  @override
  LogFilter get filter => LogFilter.startsWith(blobStream(''));

  @override
  FutureOr<ProjectionLoad<BlobsModel>> load() =>
      ProjectionLoad.initial(BlobsModel._());

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
class BlobsModel {
  final Set<String> activeIds = {};
  final Set<String> deletedIds = {};

  BlobsModel._();
}
