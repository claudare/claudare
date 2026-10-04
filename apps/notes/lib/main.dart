import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:flutter/material.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/application/note_system_provider.dart';
import 'package:notes/application/reset_database.dart';
import 'package:notes/application/event_store_provider.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/screens/loading_screen.dart';
import 'package:notes/screens/setup/actor_setup.dart';
import 'package:notes/screens/setup/sync_setup.dart';
import 'package:notes/util/get_application_directory.dart';
import 'package:path/path.dart' as path;
import 'package:time_provider/time_provider.dart';
import 'package:sync/sync.dart';

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
  late Future<void> _initialization;
  NoteApplication? _ready;
  NoteSystem? _system;
  LocalActorIdentity? _identity;
  String? _serverUrl;
  String? _group;
  bool _loading = true;

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
    _system = null;
    _identity = null;
    _serverUrl = null;
    _group = null;
    _loading = true;
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    final bootstrap = widget.bootstrap;
    final directory = await widget.applicationDirectory();
    final system = await bootstrap.initializeSystem(
      dbFilepath: path.join(directory, 'main.sqlite'),
    );
    final identity = await system.identities.getLocal();
    final serverUrl = await system.kv.get(NoteSystem.serverUrlKey);
    final group = await system.kv.get(NoteSystem.groupKey);
    if (!mounted || !identical(bootstrap, widget.bootstrap)) return;
    _system = system;
    _identity = identity;
    _serverUrl = serverUrl;
    _group = group;
    if (identity != null && serverUrl != null && group != null) {
      await _openApplication();
    }
  }

  Future<void> _openApplication() async {
    final bootstrap = widget.bootstrap;
    final ready = await bootstrap.initialize(
      system: _system!,
      actor: _identity!.publicKey.toString(),
    );
    if (mounted && identical(bootstrap, widget.bootstrap)) _ready = ready;
  }

  void _onReady() {
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _advanceSetup() {
    setState(() {
      if (_identity != null && _serverUrl != null && _group != null) {
        _loading = true;
        _initialization = _openApplication();
      }
    });
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
    Future<void> reset(bool restart) => resetApplication(
      widget.bootstrap,
      widget.applicationDirectory,
      restart: restart,
    );
    final app = MaterialApp(
      title: 'Notes App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      debugShowCheckedModeBanner: false,
      home: _loading
          ? LoadingScreen(
              key: ValueKey(_initialization),
              initialization: _initialization,
              logger: widget.bootstrap.logger,
              onReady: _onReady,
              onReset: reset,
            )
          : _identity == null
          ? ActorSetup(
              identities: _system!.identities,
              onSaved: (identity) {
                _identity = identity;
                _advanceSetup();
              },
            )
          : _serverUrl == null || _group == null
          ? SyncSetup(
              kv: _system!.kv,
              initialServerUrl: _serverUrl ?? 'ws://localhost:7000',
              initialGroup: _group ?? '0',
              onSaved: (url, group) {
                _serverUrl = url;
                _group = group;
                _advanceSetup();
              },
            )
          : const HomeScreen(),
    );
    if (ready == null) return app;
    return NoteApplicationProvider(
      application: ready,
      // TODO: this is a bit redundant...
      // Probably, each dep needs to be its own provider.
      child: NoteSystemProvider(
        system: _system!,
        child: EventStoreProvider(
          eventStore: _system!.eventStore,
          reset: reset,
          child: app,
        ),
      ),
    );
  }
}
