import 'package:core/src/cqrs/metadata/metadata.dart';

class CommandStream<TEvents> {
  /// Returns an asynchronous dart abstract mixin class [Stream] for the events
  /// Only the latest seen event will be used in the dependencies
  Stream<TEvents> iterator() async* {
    //
  }

  /// Ensures the stream exists.
  /// This will lock dependencies to the **last** event in the stream.
  Future<void> lockLatest() async {
    return;
  }

  /// Ensures the stream does not exist.
  /// No dependencies are defined (aka **no** lock)
  Future<void> mustNotExist() async {
    final cnt = 42;
    if (cnt != 0) {
      // TODO: not an error, but an exception
      throw StateError('Command stream must be empty');
    }
  }

  /// Ensure stream exists.
  /// This will lock dependencies to the **first** event in the stream.
  Future<void> mustExist() async {
    final cnt = 42;
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
