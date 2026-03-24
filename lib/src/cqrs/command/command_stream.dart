import 'package:core/src/cqrs/metadata/metadata.dart';

class CommandStream<TEvents> {
  // this is a "js iterator" thingy. Return events as a stream here... Stream.stream()...
  // make this a single subscriber
  Stream<TEvents> iterator() async* {
    //
  }

  Future<int> count() async {
    return 0;
  }

  Future<void> lock() async {
    return;
  }

  Future<void> mustNotExist() async {
    final cnt = await count();
    if (cnt != 0) {
      // TODO: not an error, but an exception
      throw StateError('Command stream must be empty');
    }
  }

  Future<void> mustExist() async {
    final cnt = await count();
    if (cnt == 0) {
      // TODO: not an error, but an exception
      throw StateError('Command stream must not be empty');
    }
  }

  // the metadata could be a class with toJson method.
  // decoding is not my problem
  void append(TEvents event, AnyMetadata? metadata) {
    return;
  }
}
