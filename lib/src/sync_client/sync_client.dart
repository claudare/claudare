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
  static const int _uploadMaxBuffer = 10;
  static const Duration _uploadInterval = Duration(milliseconds: 1000);
  // for now, the server is polled every 5 seconds
  static const Duration _downloadInterval = Duration(milliseconds: 5000);

  final RpcClient _rpcClient;
  final EventStore _eventStore;

  final StreamController<StoredEvent> _remoteEventController =
      StreamController<StoredEvent>.broadcast();
  Stream<StoredEvent> get remoteEventStream => _remoteEventController.stream;

  final SyncStateManager _stateManager = SyncStateManager();
  Stream<SyncState> get syncStateStream => _stateManager.stream;

  Timer? _uploadTimer;
  int _uploadPendingCount = 0;
  Timer? _downloadTimer;

  // latest uploaded event id... this is not needed
  late EventVectorClock _uploadedEventClock;

  SyncClient(this._rpcClient, this._eventStore) {
    _rpcClient.connectionStatusStream.listen((status) {
      final isConnected = status == RpcClientConnectionStatus.connected;

      _stateManager.setConnected(isConnected);
    });
  }

  Future<void> connect(Uri endpoint) async {
    await _rpcClient.connect(endpoint);

    _restartDownload();
  }

  Future<void> disconnect() async {
    // TODO: this wont work, as after syncDownload and syncUpload the cycle is
    // restarted... a later problem
    // this is flaky, needs a separate flag maybe?
    _uploadTimer?.cancel();
    _downloadTimer?.cancel();

    await _rpcClient.disconnect();
  }

  void dispose() {
    _uploadTimer?.cancel();
    _remoteEventController.close();
    _stateManager.dispose();
  }

  /// addEvent will serialize it to disk and perform network replication!
  Future<void> addLocalEvent(StoredEvent event) async {
    await _eventStore.storeEvent(event);

    _uploadPendingCount++;
    _restartUpload();
  }

  // TODO: this could be super flaky
  void _restartUpload() async {
    _uploadTimer?.cancel();

    if (!_stateManager.isUploading && _uploadPendingCount > _uploadMaxBuffer) {
      await syncUpload();
    }

    _uploadTimer = Timer(_uploadInterval, () async {
      if (_stateManager.isUploading) {
        // just retry later?
        _restartUpload();
        return;
      }

      if (_uploadPendingCount > 0) {
        await syncUpload();
        _restartUpload(); // always retry after uploading
      }
    });
  }

  void _restartDownload() async {
    _downloadTimer?.cancel();

    _downloadTimer = Timer(_downloadInterval, () async {
      if (!_stateManager.isDownloading) {
        await syncDownload();
      }
      _restartDownload();
    });
  }

  // this function will perform full sync, aka push and pull events with remote
  // first it will upload all missing events, then download new ones
  Future<bool> syncFull() async {
    if (!_stateManager.isConnected) {
      return false;
    }

    if (_stateManager.isDownloading || _stateManager.isUploading) {
      throw StateError('SyncFull must be run uniquely');
    }

    final localClock = _eventStore.vectorClock;

    // this can fail if the client

    try {
      final clockResult = await _rpcClient.queryClock(
        _rpcClient.serverDeviceId(),
      );
      final remoteClock = clockResult.eventClock;

      await _syncUpload(localClock, remoteClock);
      // I dont think remote clock needs to be updated
      await _syncDownload(localClock, remoteClock);

      return true;
    } catch (e) {
      print('syncFull experienced error: $e');
      return false;
    }
  }

  Future<bool> syncUpload() async {
    if (!_stateManager.isConnected) {
      return false;
    }
    // double check
    if (_stateManager.isUploading) {
      throw StateError('Only single syncUpload should be ran concurrently');
    }

    final localClock = _eventStore.vectorClock;

    try {
      final clockResult = await _rpcClient.queryClock(
        _rpcClient.serverDeviceId(),
      );
      final remoteClock = clockResult.eventClock;

      await _syncUpload(localClock, remoteClock);
      return true;
    } catch (e) {
      print('syncUpload experienced error: $e');

      return false;
    }
  }

  Future<bool> syncDownload() async {
    if (!_stateManager.isConnected) {
      return false;
    }
    // double check
    if (_stateManager.isDownloading) {
      throw StateError('Only single syncDownload should be ran concurrently');
    }

    final localClock = _eventStore.vectorClock;

    try {
      final clockResult = await _rpcClient.queryClock(
        _rpcClient.serverDeviceId(),
      );
      final remoteClock = clockResult.eventClock;

      await _syncDownload(localClock, remoteClock);
      return true;
    } catch (e) {
      print('syncDownload experienced error: $e');
      // need to determine if the error is network or logic related
      // always need to retry though
      return false;
    }
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
        final stream = _eventStore.getEvents(range, _uploadMaxBuffer);
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
    } finally {
      _stateManager.setUpload(false);
    }
  }

  Future<void> _syncDownload(
    EventVectorClock localClock,
    EventVectorClock remoteClock,
  ) async {
    _stateManager.setDownload(true);
    final range = EventVectorClockRange.betweenClocks(localClock, remoteClock);

    try {
      while (range.isNotEmpty) {
        final response = await _rpcClient.queryEvents(
          _rpcClient.serverDeviceId(),
          ProtoMessageEventQuery(range, _uploadMaxBuffer),
        );
        final events = response.events;

        for (final event in events) {
          // TODO: batch store
          await _eventStore.storeEvent(event);
          _remoteEventController.add(event);
        }
      }
    } finally {
      _stateManager.setDownload(false);
    }
  }
}
