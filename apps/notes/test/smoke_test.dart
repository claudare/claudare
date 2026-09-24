import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/main.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/screens/loading_screen.dart';
import 'package:time_provider/time_provider.dart';

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
    expect(find.byType(NoteApplicationProvider), findsOneWidget);
    expect(bootstrap.initializeCount, 1);
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
}

class _ControlledBootstrap extends NoteBootstrap {
  final Completer<NoteApplication> _application = Completer();
  int initializeCount = 0;

  _ControlledBootstrap()
    : super(
        logger: const NoopLogger(),
        timeProvider: FakeTimeProviderStatic.zero(),
      );

  @override
  Future<NoteApplication> initialize({required String eventsDbFilepath}) {
    initializeCount++;
    return _application.future;
  }

  void complete() {
    _application.complete(NoteApplication(cqrsRuntime: CqrsTestRuntime()));
  }
}

class _FailingBootstrap extends NoteBootstrap {
  int initializeCount = 0;

  _FailingBootstrap(Logger logger)
    : super(logger: logger, timeProvider: FakeTimeProviderStatic.zero());

  @override
  Future<NoteApplication> initialize({required String eventsDbFilepath}) {
    initializeCount++;
    return Future.error(StateError('startup failed'));
  }
}
