import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/main.dart';
import 'package:notes/screens/error_screen.dart';

void main() {
  testWidgets('shows and logs every terminal projection error exactly once', (
    tester,
  ) async {
    final logger = RecordingLogger();
    final application = _FailureApplication(logger);
    addTearDown(application.disposeFailureStream);
    final firstError = StateError('first projection failed');
    final secondError = ArgumentError('second projection failed');
    final firstStackTrace = StackTrace.current;
    final secondStackTrace = StackTrace.current;
    final failure = CqrsProjectionFailure([
      (error: firstError, stackTrace: firstStackTrace),
      (error: secondError, stackTrace: secondStackTrace),
    ]);
    application.retain(failure);

    await tester.pumpWidget(
      NoteApplicationProvider(
        application: application,
        child: const MyApp(home: Text('ready')),
      ),
    );

    expect(find.byType(ErrorScreen), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(ProjectionErrorDetails), findsNWidgets(2));
    expect(find.text('Error 1: $firstError'), findsOneWidget);
    expect(find.text('Stack trace:\n$firstStackTrace'), findsOneWidget);
    expect(find.text('Error 2: $secondError'), findsOneWidget);
    expect(find.text('Stack trace:\n$secondStackTrace'), findsOneWidget);
    expect(logger.entries, hasLength(2));
    expect(logger.entries[0].error, same(firstError));
    expect(logger.entries[0].stackTrace, same(firstStackTrace));
    expect(logger.entries[1].error, same(secondError));
    expect(logger.entries[1].stackTrace, same(secondStackTrace));

    application.emitRetained();
    await tester.pump();

    expect(logger.entries, hasLength(2));
  });
}

final class _FailureApplication extends NoteApplication {
  final StreamController<CqrsProjectionFailure> _failures =
      StreamController<CqrsProjectionFailure>.broadcast();
  CqrsProjectionFailure? _failure;

  _FailureApplication(Logger logger) : super.test(logger: logger);

  @override
  CqrsProjectionFailure? get runtimeFailure => _failure;

  @override
  Stream<CqrsProjectionFailure> get runtimeFailures => _failures.stream;

  void retain(CqrsProjectionFailure failure) {
    _failure = failure;
  }

  void emitRetained() {
    _failures.add(_failure!);
  }

  Future<void> disposeFailureStream() => _failures.close();
}
