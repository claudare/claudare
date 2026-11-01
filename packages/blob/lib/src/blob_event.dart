import 'dart:typed_data';

import 'package:cqrs/cqrs.dart';

sealed class BlobEvent {
  const BlobEvent();
}

class BlobCreated extends BlobEvent {
  const BlobCreated();

  static String kind = 'blob.created';
}

final class BlobCreatedCodec implements EventCodec<BlobCreated> {
  const BlobCreatedCodec();

  @override
  String get kind => BlobCreated.kind;

  @override
  Uint8List toBytes(BlobCreated event) => Uint8List(0);

  @override
  BlobCreated fromBytes(Uint8List bytes) => BlobCreated();
}
