import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:kv/kv.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/note_system.dart';
import 'package:sync/sync.dart';
import 'package:time_provider/time_provider.dart';

/// Opens the Notes database and owns its lifetime.
class NoteBootstrap {
  final Logger logger;
  final TimeProvider timeProvider;
  final IsolateSqlite _sqlite;

  Future<NoteSystem>? _systemInitialization;
  Future<NotesApp>? _initialization;
  Future<void>? _closing;
  bool _opened = false;

  NoteBootstrap({
    required this.logger,
    required this.timeProvider,
    IsolateSqlite? sqlite,
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
    return application;
  }

  Future<void> _closeDatabase() async {
    if (!_opened) return;
    _opened = false;
    await _sqlite.close();
  }

  /// Closes SQLite after any initialization in progress has settled.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
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
      await _closeDatabase();
    }
  }
}
