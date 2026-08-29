import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:id_generator/id_generator.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/screens/error_screen.dart';
import 'package:notes/screens/loading_screen.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final application = NoteApplication(
    idGenerator: IdGeneratorSecure(),
    timeProvider: SystemTimeProvider(),
    logger: ConsoleLogger(name: 'notes', minimumLevel: LogLevel.debug),
  );

  runApp(
    NoteApplicationProvider(application: application, child: const MyApp()),
  );
}

class MyApp extends StatefulWidget {
  final Widget home;

  const MyApp({super.key, this.home = const LoadingScreen()});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  StreamSubscription<CqrsProjectionFailure>? _failureSubscription;
  NoteApplication? _application;
  CqrsProjectionFailure? _failure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final application = NoteApplicationProvider.of(context);
    if (identical(_application, application)) return;

    unawaited(_failureSubscription?.cancel());
    _application = application;
    _failure = null;
    _failureSubscription = application.runtimeFailures.listen(
      (failure) => _handleFailure(application, failure),
    );

    final failure = application.runtimeFailure;
    if (failure != null) {
      _handleFailure(application, failure, notify: false);
    }
  }

  void _handleFailure(
    NoteApplication application,
    CqrsProjectionFailure failure, {
    bool notify = true,
  }) {
    if (!identical(_application, application)) return;
    if (identical(_failure, failure)) return;

    for (final entry in failure.errors) {
      application.logger.error(
        'terminal projection failure',
        entry.error,
        entry.stackTrace,
      );
    }

    if (notify) {
      setState(() => _failure = failure);
    } else {
      _failure = failure;
    }
  }

  @override
  void dispose() {
    unawaited(_failureSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final failure = _failure;
        if (failure != null) return ErrorScreen(errors: failure.errors);
        return child!;
      },
      home: widget.home,
    );
  }
}
