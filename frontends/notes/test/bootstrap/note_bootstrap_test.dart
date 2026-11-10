import 'dart:async';

import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/note_system.dart';
import 'package:time_provider/time_provider.dart';
import 'package:support_directory/support_directory.dart';

void main() {
  test('closing bootstrap stops the search projection', () async {
    final bootstrap = NoteBootstrap(
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    addTearDown(bootstrap.close);
    final system = await bootstrap.initializeSystem(
      dbFilepath: IsolateSqlite.memoryFilename,
    );
    final store = _ObservedEventStore();
    final application = await bootstrap.initialize(
      system: NoteSystem(
        identities: system.identities,
        kv: system.kv,
        eventStore: store,
      ),
      actor: 'test-actor',
    );
    await application.query.searchReady;
    expect(store.listeners, 1);

    await bootstrap.close();

    expect(store.listeners, 0);
  });

  test('keeps note history readable after SQLite is reopened', () async {
    final support = TempSupportDirectory();
    addTearDown(support.delete);
    final filepath = await support.getFilePath('main.sqlite');

    final first = NoteBootstrap(
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    addTearDown(first.close);
    final system = await first.initializeSystem(dbFilepath: filepath);
    final application = await first.initialize(
      system: system,
      actor: 'test-actor',
    );
    expect(
      await first.initialize(system: system, actor: 'test-actor'),
      same(application),
    );

    final noteId = application.generateNoteId();
    await application.command.createNote(noteId);
    await application.command.updateNoteTitle(noteId, 'Persisted title');
    await first.close();

    final second = NoteBootstrap(
      logger: const NoopLogger(),
      timeProvider: FakeTimeProviderStatic.zero(),
    );
    addTearDown(second.close);
    final reopenedSystem = await second.initializeSystem(dbFilepath: filepath);
    final reopened = await second.initialize(
      system: reopenedSystem,
      actor: 'test-actor',
    );

    expect((await reopened.query.note(noteId)).title, 'Persisted title');
    expect(await reopened.query.noteList(), hasLength(1));
    expect(
      await EventStoreTestUtils.getEventCount(reopenedSystem.eventStore),
      2,
    );
  });

  test('closes SQLite when event database migration fails', () async {
    final support = TempSupportDirectory();
    addTearDown(support.delete);
    final filepath = await support.getFilePath('main.sqlite');
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
    addTearDown(bootstrap.close);
    await expectLater(
      bootstrap.initializeSystem(dbFilepath: filepath),
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
      bootstrap.initializeSystem(dbFilepath: 'unused'),
      throwsA(same(sqlite.openError)),
    );
    expect(sqlite.closeCount, 0);
    await bootstrap.close();
    expect(sqlite.closeCount, 0);
  });
}

class _ObservedEventStore extends MemoryEventStore {
  int listeners = 0;

  @override
  Stream<EventChange> get eventChanges => Stream.multi((controller) {
    listeners++;
    final subscription = super.eventChanges.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = () async {
      await subscription.cancel();
      listeners--;
    };
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
