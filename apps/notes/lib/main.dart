import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:flutter/material.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/reset_event_database.dart';
import 'package:notes/application/event_store_provider.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/screens/loading_screen.dart';
import 'package:notes/util/get_application_directory.dart';
import 'package:path/path.dart' as path;
import 'package:time_provider/time_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final bootstrap = NoteBootstrap(
    timeProvider: SystemTimeProvider(),
    logger: ConsoleLogger(name: 'notes', minimumLevel: LogLevel.debug),
  );
  runApp(MyApp(bootstrap: bootstrap));
}

class MyApp extends StatefulWidget {
  final NoteBootstrap bootstrap;
  final Future<String> Function() applicationDirectory;

  const MyApp({
    super.key,
    required this.bootstrap,
    this.applicationDirectory = getApplicationDirectory,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late Future<NoteBootstrapResult> _initialization;
  NoteBootstrapResult? _ready;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialization = _initialize();
  }

  @override
  void didUpdateWidget(MyApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.bootstrap, widget.bootstrap)) return;

    unawaited(_closeBootstrap(oldWidget.bootstrap));
    _ready = null;
    _initialization = _initialize();
  }

  Future<NoteBootstrapResult> _initialize() async {
    final directory = await widget.applicationDirectory();
    return widget.bootstrap.initialize(
      eventsDbFilepath: path.join(directory, 'events.sqlite'),
    );
  }

  void _onReady(NoteBootstrapResult ready) {
    if (!mounted) return;
    setState(() => _ready = ready);
  }

  Future<void> _closeBootstrap(NoteBootstrap bootstrap) async {
    try {
      await bootstrap.close();
    } catch (error, stackTrace) {
      bootstrap.logger.error('Failed to close Notes', error, stackTrace);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(_closeBootstrap(widget.bootstrap));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_closeBootstrap(widget.bootstrap));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready;
    Future<void> reset() =>
        resetAndRestartNotes(widget.bootstrap, widget.applicationDirectory);
    final app = MaterialApp(
      title: 'Notes App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      home:
          ready == null
              ? LoadingScreen(
                key: ValueKey(widget.bootstrap),
                initialization: _initialization,
                logger: widget.bootstrap.logger,
                onReady: _onReady,
                onReset: reset,
              )
              : HomeScreen(application: ready.application),
    );
    if (ready == null) return app;
    return NoteApplicationProvider(
      application: ready.application,
      child: EventStoreProvider(
        eventStore: ready.eventStore,
        reset: reset,
        child: app,
      ),
    );
  }
}
