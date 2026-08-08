import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:logging/logging.dart' as package_logging;
import 'package:test/test.dart';

void main() {
  group('ConsoleLogger', () {
    test('maps every public level to its package:logging level', () async {
      final output = await _captureConsole(
        (logger) {
          logger.debug('debug message');
          logger.info('info message');
          logger.warning('warning message');
          logger.error('error message');
        },
        name: 'levels',
        minimumLevel: LogLevel.debug,
      );

      expect(output, [
        'FINE [levels]: debug message',
        'INFO [levels]: info message',
        'WARNING [levels]: warning message',
        'SEVERE [levels]: error message',
      ]);
    });

    test('filters messages below the configured minimum level', () async {
      final output = await _captureConsole(
        (logger) {
          logger.debug('hidden debug');
          logger.info('hidden info');
          logger.warning('visible warning');
          logger.error('visible error');
        },
        name: 'filter',
        minimumLevel: LogLevel.warning,
      );

      expect(output, [
        'WARNING [filter]: visible warning',
        'SEVERE [filter]: visible error',
      ]);
    });

    test('formats errors and stack traces', () async {
      final stackTrace = StackTrace.fromString('example stack trace');
      final output = await _captureConsole(
        (logger) {
          logger.error('operation failed', StateError('broken'), stackTrace);
        },
        name: 'format',
        minimumLevel: LogLevel.info,
      );

      expect(output, [
        'SEVERE [format]: operation failed\n'
            'Error: Bad state: broken\n'
            'example stack trace',
      ]);
    });

    test('stops writing after it is closed', () async {
      final output = <String>[];

      await runZoned(() async {
        final logger = ConsoleLogger(
          name: 'close',
          minimumLevel: LogLevel.debug,
        );
        logger.info('before close');
        await logger.close();
        logger.info('after close');
      }, zoneSpecification: _capturePrint(output));

      expect(output, ['INFO [close]: before close']);
    });

    test('does not modify or publish records to the root logger', () async {
      final rootLevel = package_logging.Logger.root.level;
      final rootRecords = <package_logging.LogRecord>[];
      final output = <String>[];
      final rootSubscription = package_logging.Logger.root.onRecord.listen(
        rootRecords.add,
      );

      await runZoned(() async {
        final logger = ConsoleLogger(
          name: 'detached',
          minimumLevel: LogLevel.debug,
        );
        logger.debug('detached message');
        await logger.close();
      }, zoneSpecification: _capturePrint(output));
      await rootSubscription.cancel();

      expect(package_logging.Logger.root.level, same(rootLevel));
      expect(rootRecords, isEmpty);
      expect(output, ['FINE [detached]: detached message']);
    });
  });

  test('NoopLogger is silent', () async {
    final output = <String>[];

    await runZoned(() {
      const logger = NoopLogger();
      logger.debug('debug');
      logger.info('info');
      logger.warning('warning');
      logger.error('error', StateError('broken'), StackTrace.current);
    }, zoneSpecification: _capturePrint(output));

    expect(output, isEmpty);
  });

  test('RecordingLogger records messages and diagnostics in order', () {
    final logger = RecordingLogger();
    final error = StateError('broken');
    final stackTrace = StackTrace.current;

    logger.debug('debug');
    logger.info('info');
    logger.warning('warning');
    logger.error('error', error, stackTrace);

    expect(logger.entries.map((entry) => entry.level), LogLevel.values);
    expect(logger.entries.map((entry) => entry.message), [
      'debug',
      'info',
      'warning',
      'error',
    ]);
    expect(logger.entries.last.error, same(error));
    expect(logger.entries.last.stackTrace, same(stackTrace));
  });
}

Future<List<String>> _captureConsole(
  void Function(ConsoleLogger logger) log, {
  required String name,
  required LogLevel minimumLevel,
}) async {
  final output = <String>[];

  await runZoned(() async {
    final logger = ConsoleLogger(name: name, minimumLevel: minimumLevel);
    log(logger);
    await logger.close();
  }, zoneSpecification: _capturePrint(output));

  return output;
}

ZoneSpecification _capturePrint(List<String> output) =>
    ZoneSpecification(print: (self, parent, zone, line) => output.add(line));
