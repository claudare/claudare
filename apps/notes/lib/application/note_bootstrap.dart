import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/note_application.dart';
import 'package:time_provider/time_provider.dart';

/// Opens the event database and owns its lifetime.
class NoteBootstrap {
  final Logger logger;
  final TimeProvider timeProvider;
  final IsolateSqlite _sqlite;

  Future<NoteApplication>? _initialization;
  Future<void>? _closing;

  NoteBootstrap({
    required this.logger,
    required this.timeProvider,
    IsolateSqlite? sqlite,
  }) : _sqlite = sqlite ?? IsolateSqlite();

  /// Opens and migrates [eventsDbFilepath] once.
  Future<NoteApplication> initialize({required String eventsDbFilepath}) {
    if (_closing != null) {
      throw StateError('Notes bootstrap is closed');
    }
    return _initialization ??= _open(eventsDbFilepath);
  }

  Future<NoteApplication> _open(String eventsDbFilepath) async {
    var opened = false;
    try {
      await _sqlite.open(eventsDbFilepath);
      opened = true;
      final database = SqliteEventDatabase(_sqlite);
      await database.migrate();
      final runtime = CqrsRuntime(
        eventStore: EventStore(database),
        logger: logger,
        timeProvider: timeProvider,
      );
      return NoteApplication(cqrsRuntime: runtime);
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
