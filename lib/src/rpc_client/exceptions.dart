// TODO: use https://pub.dev/packages/stack_trace for debug output

class RpcException implements Exception {
  String message;
  RpcException(this.message);

  // RpcException.debug(Object originalError, StackTrace trace)
  //   : message = '$originalError; stack: $trace';

  @override
  String toString() => 'Rpc failed: $message';
}
