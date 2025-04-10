// TODO: use https://pub.dev/packages/stack_trace for debug output

import 'package:core/protocol.dart';

class RpcException implements Exception {
  String message;
  RpcException(this.message);

  // RpcException.debug(Object originalError, StackTrace trace)
  //   : message = '$originalError; stack: $trace';

  @override
  String toString() => 'Rpc failed: $message';
}

class NetworkingException implements Exception {
  Object original;
  ProtoHeaderAck? ack;
  NetworkingException(this.original, this.ack);

  @override
  String toString() => '$ack: $original';
}
