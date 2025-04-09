import 'dart:async';

import 'package:core/src/event_store/store.dart';
import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/event_store/vector_clock_range.dart';
import 'package:core/src/protocol/proto_messages.dart';
import 'package:core/src/rpc_client/rpc_client.dart';
import 'package:core/src/rpc_client/transport.dart';
import 'package:core/src/sync_client/sync_state.dart';

class SyncClient {
  static const int _flushMaxBuffer = 10;
  static const Duration _flushInterval = Duration(milliseconds: 1000);

  final RpcClient _rpcClient;
  final StreamController<StoredEvent> _remoteEventController =
      StreamController<StoredEvent>.broadcast();

  Timer? _flushTimer;
  int _flushPendingCount = 0;

  final SyncStateManager _stateManager = SyncStateManager();

  // should this have an event store??
  final EventStore _eventStore;

  // latest uploaded event id... is this needed?
  late EventVectorClock _uploadedEventClock;

  SyncClient(this._rpcClient, this._eventStore) {
    _rpcClient.connectionStatusStream.listen((status) {
      final isConnected = status == RpcClientConnectionStatus.connected;

      _stateManager.setConnected(isConnected);
    });
  }

  Future<void> connect(Uri endpoint) async {
    await _rpcClient.connect(endpoint);
  }

  Future<void> disconnect() async {
    _flushTimer?.cancel();
    await _rpcClient.disconnect();
  }

  void dispose() {
    _flushTimer?.cancel();
    _remoteEventController.close();
    _stateManager.dispose();
  }

  Stream<StoredEvent> get remoteEventStream => _remoteEventController.stream;

  /// addEvent will serialize it to disk and perform network replication!
  Future<void> addLocalEvent(StoredEvent event) async {
    await _eventStore.storeEvent(event);

    _onLocalEvent();
  }

  // TODO: this could be super flaky
  void _onLocalEvent() async {
    _flushTimer?.cancel();
    _flushPendingCount++;

    if (!_stateManager.isUploading && _flushPendingCount > _flushMaxBuffer) {
      await syncUpload();
    }

    _flushTimer = Timer(_flushInterval, () async {
      if (!_stateManager.isUploading && _flushPendingCount > 0) {
        await syncUpload();
        _onLocalEvent(); // Reset timer after the upload
      }
    });
  }

  // this function will perform full sync, aka push and pull events with remote
  // first it will upload all missing events, then download new ones
  Future<void> syncFull() async {
    final localClock = _eventStore.vectorClock;

    final clockResult = await _rpcClient.queryClock(
      _rpcClient.serverDeviceId(),
    );
    final remoteClock = clockResult.eventClock;

    await _syncUpload(localClock, remoteClock);
    // I dont think remote clock needs to be updated
    await _syncDownload(localClock, remoteClock);
  }

  Future<void> syncUpload() async {
    final localClock = _eventStore.vectorClock;
    final clockResult = await _rpcClient.queryClock(
      _rpcClient.serverDeviceId(),
    );
    final remoteClock = clockResult.eventClock;

    await _syncUpload(localClock, remoteClock);
  }

  Future<void> syncDownload() async {
    final localClock = _eventStore.vectorClock;
    final clockResult = await _rpcClient.queryClock(
      _rpcClient.serverDeviceId(),
    );
    final remoteClock = clockResult.eventClock;

    await _syncDownload(localClock, remoteClock);
  }

  Future<void> _syncUpload(
    EventVectorClock localClock,
    EventVectorClock remoteClock,
  ) async {
    if (_stateManager.isUploading) {
      throw StateError('Cannot upload as already uploading');
    }
    _stateManager.setUpload(true);

    final range = EventVectorClockRange.betweenClocks(remoteClock, localClock);

    try {
      while (range.isNotEmpty) {
        final stream = _eventStore.getEvents(range, _flushMaxBuffer);
        final events = await stream.toList();

        await _rpcClient.uploadEvents(
          _rpcClient.serverDeviceId(),
          ProtoMessageEventValue(events),
        );

        // advance ids only after the upload? or before?
        for (final event in events) {
          range.advanceById(event.id);
          _uploadedEventClock.update(event.id);
        }
      }
    } catch (e) {
      // TODO: what happens here?
      // it is normal to be offline
      // slow bad networks will always create issues
      rethrow;
    } finally {
      _stateManager.setUpload(false);
    }
  }

  Future<void> _syncDownload(
    EventVectorClock localClock,
    EventVectorClock remoteClock,
  ) async {
    final range = EventVectorClockRange.betweenClocks(localClock, remoteClock);

    while (range.isNotEmpty) {
      final response = await _rpcClient.queryEvents(
        _rpcClient.serverDeviceId(),
        ProtoMessageEventQuery(range, _flushMaxBuffer),
      );
      final events = response.events;

      for (final event in events) {
        // TODO: batch store
        await _eventStore.storeEvent(event);
      }
    }
  }
}
