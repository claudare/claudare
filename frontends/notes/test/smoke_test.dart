import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/main.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/screens/loading_screen.dart';
import 'package:time_provider/time_provider.dart';

import 'setup/setup_test_helpers.dart';

void main() {
  testWidgets('shows loading until the application is ready', (tester) async {
    final bootstrap = _ControlledBootstrap();
    await tester.pumpWidget(
      MyApp(bootstrap: bootstrap, applicationDirectory: () async => 'unused'),
    );
    await tester.pump();

    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    bootstrap.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LoadingScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(NotesAppProvider), findsOneWidget);
    expect(bootstrap.initializeCount, 1);
  });

  testWidgets('settings can read the saved sync values through navigation', (
    tester,
  ) async {
    final bootstrap = _ControlledBootstrap();
    await tester.pumpWidget(
      MyApp(bootstrap: bootstrap, applicationDirectory: () async => 'unused'),
    );
    bootstrap.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('This device actor key'), findsOneWidget);
    expect(find.text('test-actor'), findsOneWidget);
    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('ws://localhost:7000 @ 0'), findsOneWidget);
    await tester.tap(find.text('ws://localhost:7000 @ 0'));
    await tester.pumpAndSettle();
    expect(find.text('Transport settings'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Group'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Server URL'), findsOneWidget);
    expect(find.text('ws://localhost:7000'), findsOneWidget);
  });

  testWidgets('shows a startup error inline and initializes only once', (
    tester,
  ) async {
    final logger = RecordingLogger();
    final bootstrap = _FailingBootstrap(logger);
    final app = MyApp(
      bootstrap: bootstrap,
      applicationDirectory: () async => 'unused',
    );

    await tester.pumpWidget(app);
    await tester.pump();

    expect(find.byType(LoadingScreen), findsOneWidget);
    expect(find.text('Could not open Notes'), findsOneWidget);
    expect(find.textContaining('startup failed'), findsOneWidget);
    expect(bootstrap.initializeCount, 1);
    expect(logger.entries.where((entry) => entry.error != null), hasLength(1));

    await tester.pumpWidget(app);
    await tester.pump();

    expect(bootstrap.initializeCount, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('startup error offers reset confirmation', (tester) async {
    final bootstrap = _FailingBootstrap(const NoopLogger());
    await tester.pumpWidget(
      MyApp(bootstrap: bootstrap, applicationDirectory: () async => 'unused'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset database'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Could not open Notes'), findsOneWidget);
  });
}

class _ControlledBootstrap extends NoteBootstrap {
  final Completer<NotesApp> _application = Completer();
  int initializeCount = 0;

  _ControlledBootstrap()
    : super(
        logger: const NoopLogger(),
        timeProvider: FakeTimeProviderStatic.zero(),
      );

  @override
  Future<NoteSystem> initializeSystem({required String dbFilepath}) async =>
      testSystem();

  @override
  Future<NotesApp> initialize({
    required NoteSystem system,
    required String actor,
  }) {
    initializeCount++;
    return _application.future;
  }

  void complete() {
    final eventStore = MemoryEventStore();
    _application.complete(
      NotesApp(cqrsRuntime: CqrsTestRuntime(eventStore: eventStore)),
    );
  }
}

class _FailingBootstrap extends NoteBootstrap {
  int initializeCount = 0;

  _FailingBootstrap(Logger logger)
    : super(logger: logger, timeProvider: FakeTimeProviderStatic.zero());

  @override
  Future<NoteSystem> initializeSystem({required String dbFilepath}) {
    initializeCount++;
    return Future.error(StateError('startup failed'));
  }
}
