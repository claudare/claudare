import 'dart:typed_data';

import 'package:stream_channel/stream_channel.dart';

enum RpcClientConnectionStatus { disconnected, connecting, connected }

abstract class RpcClientTransport extends StreamChannelMixin<Uint8List>
    implements StreamChannel<Uint8List> {
  RpcClientConnectionStatus get connectionStatus;
  Stream<RpcClientConnectionStatus> get connectionStatusStream;

  Future<void> connect(Uri uri);
  Future<void> disconnect();
}
