import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:kv/kv.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/note_system.dart';
import 'package:sync/sync.dart';
import 'package:time_provider/time_provider.dart';

/// Creates a fresh transport for the saved Notes configuration.
typedef NoteTransportFactory = Transport Function({
  required String url,
  required String actor,
  required String group,
});

/// Owns the Notes database and optional background sync lifetime.
class NoteBootstrap {
  final Logger logger;
  final TimeProvider timeProvider;
  final IsolateSqlite _sqlite;
  final NoteTransportFactory? _createTransport;
  SyncCoordinator? _syncCoordinator;
  String _syncUnavailableReason = 'Disabled';
  NoteSystem? _syncSystem;
  String? _syncActor;
  int _syncGeneration = 0;

  /// The current coordinator, when sync is enabled and configured.
  SyncCoordinator? get syncCoordinator => _syncCoordinator;

  /// Explains why there is no current coordinator.
  String get syncUnavailableReason => _syncUnavailableReason;

  Future<NoteSystem>? _systemInitialization;
  Future<NotesApp>? _initialization;
  Future<void>? _closing;
  bool _opened = false;

  NoteBootstrap({
    required this.logger,
    required this.timeProvider,
    IsolateSqlite? sqlite,
    this._createTransport,
  }) : _sqlite = sqlite ?? IsolateSqlite();

  /// Opens and migrates all stores in [dbFilepath] once.
  Future<NoteSystem> initializeSystem({required String dbFilepath}) {
    if (_closing != null) throw StateError('Notes bootstrap is closed');
    return _systemInitialization ??= _initializeSystem(dbFilepath);
  }

  Future<NoteSystem> _initializeSystem(String filepath) async {
    try {
      await _sqlite.open(filepath);
      _opened = true;
      final identities = SqliteActorIdentityStore(_sqlite);
      final kv = SqliteKv(_sqlite);
      final eventStore = SqliteEventStore(_sqlite);
      await identities.migrate();
      await kv.migrate();
      await eventStore.migrate();
      return NoteSystem(identities: identities, kv: kv, eventStore: eventStore);
    } catch (error, stackTrace) {
      try {
        await _closeDatabase();
      } catch (closeError, closeStackTrace) {
        logger.error(
          'Failed to close the database after initialization failed',
          closeError,
          closeStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Creates Notes over the migrated [system] after actor setup.
  Future<NotesApp> initialize({
    required NoteSystem system,
    required String actor,
  }) {
    if (_closing != null) throw StateError('Notes bootstrap is closed');
    return _initialization ??= _initialize(system, actor);
  }

  Future<NotesApp> _initialize(NoteSystem system, String actor) async {
    final runtime = CqrsRuntime(
      eventStore: system.eventStore,
      actor: actor,
      logger: logger,
      timeProvider: timeProvider,
    );
    final application = NotesApp(cqrsRuntime: runtime);
    // preload the note list for speed and to reveal any schema-breaking changes
    await application.query.noteList();
    _syncSystem = system;
    _syncActor = actor;
    if (_closing == null) await _reloadSync(system, actor);
    return application;
  }

  /// Applies saved transport settings without waiting for network connectivity.
  Future<void> restartSync() {
    if (_closing != null) throw StateError('Notes bootstrap is closed');
    final system = _syncSystem;
    final actor = _syncActor;
    if (system == null || actor == null) {
      throw StateError('Notes has not been initialized');
    }
    return _reloadSync(system, actor);
  }

  Future<void> _reloadSync(NoteSystem system, String actor) async {
    final generation = ++_syncGeneration;
    final values = await Future.wait<Object?>([
      system.kv.getBool(NoteSystem.syncEnabledKey),
      system.kv.getString(NoteSystem.serverUrlKey),
      system.kv.getString(NoteSystem.groupKey),
    ]);
    final enabled = values[0] as bool?;
    final url = values[1] as String?;
    final group = values[2] as String?;
    if (_closing != null || generation != _syncGeneration) return;
    final previous = _syncCoordinator;
    _syncCoordinator = null;
    await previous?.close();
    if (_closing != null || generation != _syncGeneration) return;
    if (enabled != true) {
      _syncUnavailableReason = 'Disabled';
      return;
    }
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty ||
        group == null ||
        group.trim().isEmpty) {
      _syncUnavailableReason = 'Not configured';
      return;
    }
    final ids = IdGeneratorRandom();
    final coordinator = _syncCoordinator = SyncCoordinator(
      timeProvider: timeProvider,
      eventStore: system.eventStore,
      identityStore: system.identities,
      createTransport: () =>
          _createTransport?.call(url: url!, actor: actor, group: group) ??
          WebSocketProxyTransport(
            baseUrl: url!,
            thisActor: actor,
            group: group,
            logger: logger,
            idGenerator: ids,
            timeProvider: timeProvider,
          ),
      logger: logger,
    );
    coordinator.start();
  }

  Future<void> _closeDatabase() async {
    if (!_opened) return;
    _opened = false;
    await _sqlite.close();
  }

  /// Closes SQLite after any initialization in progress has settled.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _syncGeneration++;
    try {
      final systemInitialization = _systemInitialization;
      if (systemInitialization != null) {
        try {
          await systemInitialization;
        } catch (_) {
          // System initialization already attempted cleanup.
        }
      }
      final initialization = _initialization;
      if (initialization != null) {
        try {
          await initialization;
        } catch (_) {
          // Application initialization reports its error to the caller.
        }
      }
    } finally {
      await _syncCoordinator?.close();
      await _closeDatabase();
    }
  }
}
