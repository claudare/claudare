// [Application] is the top-level class that holds everything needed to initialize
// the application and to do local state
import 'package:core/cqrs.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';

class Application {
  final IsolateSqlite sqliteDb;
  final SqliteEventStore eventStore;
  final IdGenerator idGenerator;
  final TimeProvider timeProvider;
  final NotesRuntime notesRuntime;

  const Application({
    required this.sqliteDb,
    required this.eventStore,
    required this.idGenerator,
    required this.timeProvider,
    required this.notesRuntime,
  });

  Future<void> initialize() async {
    // TODO: abstract this too?
    await sqliteDb.open();

    // TODO: abstract event store initialization...
    await eventStore.migrate();

    await notesRuntime.initialize();

    await Future.delayed(const Duration(seconds: 1));
  }

  // used for ApplicationProvider notifier
  @override
  bool operator ==(Object other) {
    return identical(this, other);
  }

  // TODO: this may not work!!!
  @override
  int get hashCode => Object.hash(eventStore, notesRuntime);
}
