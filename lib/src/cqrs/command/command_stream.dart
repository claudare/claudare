class CommandStream<TEvents> {
  // this is a "js iterator" thingy. Return events as a stream here... Stream.stream()...
  Stream<TEvents> iterator() async* {
    //
  }

  Future<int> count() async {
    return 0;
  }

  Future<void> lock() async {
    return;
  }

  void append(TEvents event, Map<String, dynamic>? metadata) {
    return;
  }
}
