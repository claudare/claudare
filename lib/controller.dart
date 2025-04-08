import 'dart:convert';

import 'package:core/utils.dart';
import 'package:messagepack/messagepack.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:restart_app/restart_app.dart';

import 'package:core/core.dart';
import 'package:core/database.dart';
import 'package:core/event_store.dart';
import 'package:notes_app_v0/app_store.dart';
import 'package:notes_app_v0/events.dart';
import 'package:notes_app_v0/repo.dart';

// [Controller] (real name btd) glues all services together
// network layer should be managed here
// because of the inheritedWidget and path_provider, all of this has to be late
class Controller {
  late EventStore _eventStore;
  late AppStore _appStore;
  late Repo repo;

  final GenericIdGenerator _genericIdGen;
  final EventIdGenerator _eventIdGen;

  Controller(DeviceId thisDeviceId)
    : _genericIdGen = GenericIdGenerator.withCounter(
        thisDeviceId,
        Counter16.random(),
      ),
      _eventIdGen = EventIdGenerator(thisDeviceId);

  Future<void> initTemporary() async {
    _eventStore = EventStore.temporary();
    _appStore = AppStore.temporary();
    repo = Repo.empty(_appStore);
  }

  Future<void> initPersisted() async {
    final docDir = await getApplicationDocumentsDirectory();
    if (!await docDir.exists()) {
      await docDir.create(recursive: true);
    }

    print('using docDir $docDir');
    // load device id from somewhere...
    // maybe its part of the system database/repo?

    _eventStore = EventStore(path.join(docDir.path, 'event_store.db'));
    _appStore = AppStore(path.join(docDir.path, 'app_store.db'));
    repo = Repo.empty(_appStore);
  }

  Future<void> loadRepo() async {
    await _eventStore.init();
    await _appStore.init();
    await repo.loadFromAppStore();
  }

  Future<void> deinit() async {
    repo.deinit();
    await _appStore.deinit();
    await _eventStore.deinit();
  }

  Future<void> applyEventsFromClock(EventVectorClock fromClock) async {
    // reload all events like so:
    // this is a pretty elegant solution in my opinion
    final finalVectorClock = _eventStore.vectorClock.copyWith({});
    final range = EventVectorClockRange.betweenClocks(
      fromClock,
      finalVectorClock,
    );

    while (!range.isEmpty) {
      final stream = _eventStore.getEvents(range, 10);
      await for (final eventRaw in stream) {
        final eventId = eventRaw.id;

        final eventParsed = NoteEvent.unpackBytes(eventRaw.bytes);

        await repo.processEvent(eventId, eventParsed);
        range.advanceById(eventId);
      }
    }
  }

  Future<void> applyEventsFromStart() async {
    await applyEventsFromClock(EventVectorClock.empty());
  }

  EventId _newEventId({Timestamp? timestamp}) {
    return _eventIdGen.next(timestamp ?? Timestamp.now());
  }

  GenericId newGenericId(String scope, {Timestamp? timestamp}) {
    return _genericIdGen.next(scope, timestamp ?? Timestamp.now());
  }

  Future<void> localEventSubmit(NoteEvent event) async {
    final eventId = _newEventId();
    final p = Packer();
    event.pack(p);
    final envelope = StoredEvent(eventId, p.takeBytes());

    await _eventStore.storeEvent(envelope);
    await repo.processEvent(eventId, event);
  }

  Future<FileSize> allDatabaseSizes() async {
    final eventStoreSize = await databaseGetSizeBytes(_eventStore);
    final appStoreSize = await databaseGetSizeBytes(_appStore);

    return FileSize(eventStoreSize + appStoreSize);
  }

  Future<int> eventCount() async {
    return await _eventStore.eventCount();
  }

  Future<void> rebuildFromStart() async {
    // await deinit();

    await databaseDELETE(_appStore);

    await initPersisted();
    await loadRepo();

    await applyEventsFromStart();
  }

  Future<void> deleteAllDataAndRestart() async {
    await deinit();

    await databaseDELETE(_eventStore);
    await databaseDELETE(_appStore);

    Restart.restartApp();
  }

  // used for controller provider notifier
  @override
  bool operator ==(Object other) {
    return identical(this, other);
  }

  @override
  int get hashCode => Object.hash(_eventStore, _appStore, repo);
}
