import 'dart:async';

import 'package:logging/logging.dart' as package_logging;

import 'log_level.dart';
import 'logger.dart';

final class ConsoleLogger implements Logger {
  final String name;
  final LogLevel minimumLevel;
  final package_logging.Logger _logger;
  late final StreamSubscription<package_logging.LogRecord> _subscription;

  ConsoleLogger({required this.name, required this.minimumLevel})
    : _logger = package_logging.Logger.detached(name) {
    _logger.level = _packageLevel(minimumLevel);
    _subscription = _logger.onRecord.listen(_writeToConsole);
  }

  Future<void> close() => _subscription.cancel();

  @override
  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.log(package_logging.Level.FINE, message, error, stackTrace);
  }

  @override
  void info(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.log(package_logging.Level.INFO, message, error, stackTrace);
  }

  @override
  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.log(package_logging.Level.WARNING, message, error, stackTrace);
  }

  @override
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.log(package_logging.Level.SEVERE, message, error, stackTrace);
  }

  void _writeToConsole(package_logging.LogRecord record) {
    final output = StringBuffer(
      '${record.level.name} [${record.loggerName}]: ${record.message}',
    );
    if (record.error != null) {
      output.write('\nError: ${record.error}');
    }
    if (record.stackTrace != null) {
      output.write('\n${record.stackTrace}');
    }

    // ignore: avoid_print
    print(output);
  }
}

package_logging.Level _packageLevel(LogLevel level) => switch (level) {
  LogLevel.debug => package_logging.Level.FINE,
  LogLevel.info => package_logging.Level.INFO,
  LogLevel.warning => package_logging.Level.WARNING,
  LogLevel.error => package_logging.Level.SEVERE,
};
