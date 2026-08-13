// [Application] is the top-level class that holds everything needed to initialize
// the application and to do local state
import 'package:cqrs/cqrs.dart';
import 'package:id_generator/id_generator.dart';
import 'package:time_provider/time_provider.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/runtime/notes_runtime.dart';
import 'package:path/path.dart' as path;

class Application {
  final IsolateSqlite sqliteDb;
  final IsolateSqlite searchDb;

  // TODO: this should be an EventStore interface
  final SqliteEventStore eventStore;
  final NotesRuntime notesRuntime;

  const Application({
    required this.sqliteDb,
    required this.searchDb,
    required this.eventStore,
    required IdGenerator idGenerator,
    required TimeProvider timeProvider,
    required this.notesRuntime,
  });

  Future<void> initialize(String applicationDirectory) async {
    final mainDbPath = path.join(applicationDirectory, 'notes.db');
    await sqliteDb.open(mainDbPath);

    final searchDbPath = path.join(applicationDirectory, 'search.db');
    await searchDb.open(searchDbPath);

    await eventStore.migrate();
    await notesRuntime.initialize();
    // await Future.delayed(const Duration(seconds: 1));
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other);
  }

  @override
  int get hashCode => Object.hash(eventStore, notesRuntime);
}
