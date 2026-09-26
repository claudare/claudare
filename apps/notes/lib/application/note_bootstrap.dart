import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/note_application.dart';
import 'package:time_provider/time_provider.dart';

const devActor = 'notes-dev';

/// Opens the event database and owns its lifetime.
class NoteBootstrap {
  final Logger logger;
  final TimeProvider timeProvider;
  final IsolateSqlite _sqlite;

  Future<NoteBootstrapResult>? _initialization;
  Future<void>? _closing;

  NoteBootstrap({
    required this.logger,
    required this.timeProvider,
    IsolateSqlite? sqlite,
  }) : _sqlite = sqlite ?? IsolateSqlite();

  /// Opens and migrates [eventsDbFilepath] once.
  Future<NoteBootstrapResult> initialize({required String eventsDbFilepath}) {
    if (_closing != null) {
      throw StateError('Notes bootstrap is closed');
    }
    return _initialization ??= _initialize(eventsDbFilepath);
  }

  Future<NoteBootstrapResult> _initialize(String eventsDbFilepath) async {
    var opened = false;
    try {
      await _sqlite.open(eventsDbFilepath);
      opened = true;

      final eventStore = SqliteEventStore(_sqlite);
      final runtime = CqrsRuntime(
        eventStore: eventStore,
        actor: devActor,
        logger: logger,
        timeProvider: timeProvider,
      );
      final application = NoteApplication(cqrsRuntime: runtime);

      await eventStore.migrate();
      // resolve the notelist so that its snapshot is resolved on startup
      // also, this will catch any migration replacement issues right away
      await application.query.noteList();

      return NoteBootstrapResult(
        application: application,
        eventStore: eventStore,
      );
    } catch (error, stackTrace) {
      if (opened) {
        try {
          await _sqlite.close();
        } catch (closeError, closeStackTrace) {
          logger.error(
            'Failed to close the event database after initialization failed',
            closeError,
            closeStackTrace,
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Closes SQLite after any initialization in progress has settled.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    final initialization = _initialization;
    if (initialization != null) {
      try {
        await initialization;
      } catch (_) {
        // Initialization already attempted to close SQLite.
        return;
      }
    }
    await _sqlite.close();
  }
}

/// The application and event store opened by one [NoteBootstrap].
class NoteBootstrapResult {
  final NoteApplication application;
  final EventStore eventStore;

  const NoteBootstrapResult({
    required this.application,
    required this.eventStore,
  });
}
