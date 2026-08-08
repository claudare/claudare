import 'log_level.dart';

class LogEntry {
  final LogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  const LogEntry({
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });
}
