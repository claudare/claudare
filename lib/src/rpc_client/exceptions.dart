class RpcException implements Exception {
  String message;
  RpcException(this.message);

  // RpcException.debug(Object originalError, StackTrace trace)
  //   : message = '$originalError; stack: $trace';

  @override
  String toString() => 'Rpc failed: $message';
}
