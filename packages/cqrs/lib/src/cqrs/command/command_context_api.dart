import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/src/cqrs/command/command_context.dart' show CommandStream;

/// Provides streams and logging to command handlers.
abstract interface class CommandContextApi {
  Logger get logger;

  CommandStream<TEvent> stream<TEvent extends Object>(String streamPath);
}
