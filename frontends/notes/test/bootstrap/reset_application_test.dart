import 'dart:async';
import 'dart:io';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/reset_database.dart';
import 'package:support_directory/support_directory.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('restart');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> operations;
  late _RecordingBootstrap bootstrap;
  late _RecordingSupportDirectory support;

  setUp(() {
    operations = [];
    bootstrap = _RecordingBootstrap(operations);
    support = _RecordingSupportDirectory(operations);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'restartApp');
      expect(call.arguments['mode'], 'process');
      operations.add('restart');
      return 'ok';
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  for (final restart in [false, true]) {
    test('reset with restart=$restart closes before deleting', () async {
      await resetApplication(bootstrap, support, restart: restart);

      expect(operations, ['close', 'delete', if (restart) 'restart']);
    });
  }

  test('reset waits for resource closure before deleting', () async {
    final closed = Completer<void>();
    bootstrap.closeDelay = closed.future;

    final resetting = resetApplication(bootstrap, support, restart: false);
    expect(operations, ['close']);
    closed.complete();
    await resetting;

    expect(operations, ['close', 'delete']);
  });

  test('closure failure prevents deletion and restart', () async {
    final failure = Exception('close failed');
    bootstrap.closeFailure = failure;

    await expectLater(
      resetApplication(bootstrap, support, restart: true),
      throwsA(same(failure)),
    );
    expect(operations, ['close']);
  });

  test('deletion failure prevents restart', () async {
    final failure = FileSystemException('delete failed');
    support.deleteFailure = failure;

    await expectLater(
      resetApplication(bootstrap, support, restart: true),
      throwsA(same(failure)),
    );
    expect(operations, ['close', 'delete']);
  });
}

class _RecordingBootstrap extends NoteBootstrap {
  final List<String> operations;
  Future<void>? closeDelay;
  Exception? closeFailure;

  _RecordingBootstrap(this.operations)
    : super(
        logger: const NoopLogger(),
        timeProvider: FakeTimeProviderStatic.zero(),
      );

  @override
  Future<void> close() async {
    operations.add('close');
    await closeDelay;
    if (closeFailure != null) throw closeFailure!;
  }
}

class _RecordingSupportDirectory implements SupportDirectory {
  final List<String> operations;
  Exception? deleteFailure;

  _RecordingSupportDirectory(this.operations);

  @override
  Future<Directory> getDirectory() async =>
      throw StateError('Reset must not create a directory');

  @override
  Future<String> getFilePath(String filename) async =>
      throw StateError('Reset must not resolve a file path');

  @override
  Future<void> delete() async {
    operations.add('delete');
    if (deleteFailure != null) throw deleteFailure!;
  }
}
