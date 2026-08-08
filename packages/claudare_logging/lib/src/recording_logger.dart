import 'log_entry.dart';
import 'log_level.dart';
import 'logger.dart';

final class RecordingLogger implements Logger {
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _record(LogLevel.debug, message, error, stackTrace);
  }

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) {
    _record(LogLevel.info, message, error, stackTrace);
  }

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _record(LogLevel.warning, message, error, stackTrace);
  }

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _record(LogLevel.error, message, error, stackTrace);
  }

  void _record(
    LogLevel level,
    String message,
    Object? error,
    StackTrace? stackTrace,
  ) {
    _entries.add(
      LogEntry(
        level: level,
        message: message,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }
}
