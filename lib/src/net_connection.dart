import 'dart:typed_data';

import 'package:stream_channel/stream_channel.dart';

abstract class NetConnection extends StreamChannelMixin<Uint8List>
    implements StreamChannel<Uint8List> {
  // Future<void> connect(Uri uri);
  Future<void> disconnect();
}

class NetConnectionException implements Exception {
  Object original;
  NetConnectionException(this.original);

  @override
  String toString() => original.toString();
}
