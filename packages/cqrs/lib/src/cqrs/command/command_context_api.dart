import 'dart:typed_data';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart' show CommandStream;

/// Provides streams, blob writes, IDs, and logging to command handlers.
abstract interface class CommandContextApi {
  Logger get logger;

  /// Generates an ID using the injected generator.
  String generateId();

  /// Replay streams to ensure data consistency and to establish dependencies.
  CommandStream<TEvent> stream<TEvent extends Object>(String streamPath);

  /// Registers a snapshot of [data] for persistence with this command.
  void saveBlob(String id, Uint8List data);
}
