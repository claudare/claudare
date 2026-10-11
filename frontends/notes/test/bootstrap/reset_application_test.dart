import 'dart:async';
import 'dart:io';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/screens/restart_required_screen.dart';
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

  Future<void> openScreen(
    WidgetTester tester, {
    TargetPlatform platform = TargetPlatform.android,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: RestartRequiredScreen(
        bootstrap: bootstrap,
        supportDirectory: support,
        resetDatabase: true,
      ),
    ),
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('reset closes before deleting on ${platform.name}', (
      tester,
    ) async {
      await openScreen(tester, platform: platform);
      await tester.pumpAndSettle();

      expect(operations, ['close', 'delete']);
      expect(find.text('Restart required'), findsOneWidget);
      expect(
        find.text(
          'The application needs to be restarted due to a database change.',
        ),
        findsOneWidget,
      );
      if (platform == TargetPlatform.iOS) {
        expect(find.text('Restart now'), findsNothing);
      } else {
        await tester.tap(find.text('Restart now'));
        await tester.pumpAndSettle();
        expect(operations, ['close', 'delete', 'restart']);
      }
    });
  }

  testWidgets('reset waits for resource closure before deleting', (
    tester,
  ) async {
    final closed = Completer<void>();
    bootstrap.closeDelay = closed.future;

    await openScreen(tester);
    expect(operations, ['close']);
    closed.complete();
    await tester.pumpAndSettle();

    expect(operations, ['close', 'delete']);
  });

  testWidgets('closure failure prevents deletion and restart', (tester) async {
    final failure = Exception('close failed');
    bootstrap.closeFailure = failure;

    await openScreen(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not reset Notes'), findsOneWidget);
    expect(find.text('Restart now'), findsNothing);
    expect(operations, ['close']);
  });

  testWidgets('deletion failure prevents restart', (tester) async {
    final failure = FileSystemException('delete failed');
    support.deleteFailure = failure;

    await openScreen(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not reset Notes'), findsOneWidget);
    expect(find.text('Restart now'), findsNothing);
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
