import 'package:core/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes_app_v0/application.dart';
import 'package:notes_app_v0/application_provider.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_internal_repo.dart';
import 'package:notes_app_v0/repo/note/sqlite_note_read_model.dart';
import 'package:notes_app_v0/runtime/notes_runtime.dart';
import 'package:notes_app_v0/screens/loading_screen.dart';
import 'package:path/path.dart' as path show join;
import 'package:path_provider/path_provider.dart';
import 'package:core/id_generator.dart';
import 'package:core/time_provider.dart';

// TODO: sqlite database path determining is async...
Future<String> getDatabasePath() async {
  final docDir = await getApplicationDocumentsDirectory();
  if (!await docDir.exists()) {
    await docDir.create(recursive: true);
  }

  return path.join(docDir.path, 'event_store.db');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final idGenerator = RandomIdGenerator();
  final timeProvider = SystemTimeProvider();

  final cqrsConfig = CqrsRuntimeConfig(
    idGenerator: idGenerator,
    timeProvider: timeProvider,
    eventStorePageSize: 20,
  );

  final sqliteDb = IsolateSqlite(IsolateSqlite.memoryInitFn);
  final eventStore = SqliteEventStore(sqliteDb);

  final noteInternalRepo = SqliteNoteInternalRepo(sqliteDb);
  final noteReadModel = SqliteNoteReadModel(sqliteDb);

  final application = Application(
    sqliteDb: sqliteDb,
    eventStore: eventStore,
    notesRuntime: NotesRuntime(
      eventStore: eventStore,
      cqrsConfig: cqrsConfig,
      noteInternalRepo: noteInternalRepo,
      noteReadModel: noteReadModel,
    ),
  );

  runApp(ApplicationProvider(application: application, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notes App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const LoadingScreen(),
    );
  }
}
