import 'dart:io';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:path/path.dart' as path;
import 'package:time_provider/time_provider.dart';

void main() {
  test('keeps note history readable after SQLite is reopened', () async {
    final directory = await Directory.systemTemp.createTemp('notes-bootstrap-');
    addTearDown(() => directory.delete(recursive: true));
    final filepath = path.join(directory.path, 'events.sqlite');

    final first = NoteBootstrap(
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    addTearDown(first.close);
    final application = await first.initialize(eventsDbFilepath: filepath);
    expect(
      await first.initialize(eventsDbFilepath: filepath),
      same(application),
    );

    final noteId = await application.application.command.createNote();
    await application.application.command.updateNoteTitle(
      noteId,
      'Persisted title',
    );
    await first.close();

    final second = NoteBootstrap(
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    addTearDown(second.close);
    final reopened = await second.initialize(eventsDbFilepath: filepath);

    expect(
      (await reopened.application.query.note(noteId))?.title,
      'Persisted title',
    );
    expect((await reopened.application.query.noteList()).activeCount, 1);
    expect((await reopened.eventStore.getStatistics()).eventCount, 2);
  });

  test('closes SQLite when event database migration fails', () async {
    final directory = await Directory.systemTemp.createTemp('notes-migration-');
    addTearDown(() => directory.delete(recursive: true));
    final filepath = path.join(directory.path, 'events.sqlite');
    final sqlite = IsolateSqlite();
    await sqlite.open(filepath);
    await sqlite.execute('CREATE TABLE migrations_event_database (wrong INT)');
    await sqlite.close();

    final tracked = _CountingSqlite();
    final bootstrap = NoteBootstrap(
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
      sqlite: tracked,
    );
    await expectLater(
      bootstrap.initialize(eventsDbFilepath: filepath),
      throwsA(isA<Exception>()),
    );
    expect(tracked.closeCount, 1);
    await bootstrap.close();
    expect(tracked.closeCount, 1);
  });

  test('preserves an open error without closing an unopened SQLite', () async {
    final sqlite = _FailingOpenSqlite();
    final bootstrap = NoteBootstrap(
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
      sqlite: sqlite,
    );

    await expectLater(
      bootstrap.initialize(eventsDbFilepath: 'unused'),
      throwsA(same(sqlite.openError)),
    );
    expect(sqlite.closeCount, 0);
    await bootstrap.close();
    expect(sqlite.closeCount, 0);
  });
}

class _CountingSqlite extends IsolateSqlite {
  int closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
    await super.close();
  }
}

class _FailingOpenSqlite extends _CountingSqlite {
  final openError = StateError('could not open events');

  @override
  Future<void> open(
    String filename, {
    String? vfs,
    Object? mode,
    bool uri = false,
    bool? mutex,
    SetupFn? setup,
  }) async {
    throw openError;
  }
}
