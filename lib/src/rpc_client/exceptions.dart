class RpcException implements Exception {
  String message;
  RpcException(this.message);

  @override
  String toString() => 'Rpc failed. Server error message: $message';
}
