// old lengthly implementation, going to keep it for a reference

// import 'dart:async';

// import 'package:core/src/event_store/store.dart';
// import 'package:core/src/event_store/stored_event.dart';
// import 'package:core/src/event_store/vector_clock.dart';
// import 'package:core/src/event_store/vector_clock_range.dart';
// import 'package:core/src/protocol/proto_messages.dart';
// import 'package:core/src/client_transport/transport.dart';
// import 'package:core/src/sync_client/sync_state.dart';
// import 'package:core/src/utils/retry_strategy.dart';
// import 'package:pointycastle/pointycastle.dart';

// // TODO: rename to SyncManager
// // it has a bool field setActiveState(bool)
// // it internally attempts to activate itself by invoking connect on the transport (client)
// // all the retry strategies are done in here, not in the RpcClient
// // it will not do full sync right away.
// // It will upload/download at the same time
// // upload will be done via a queue if client is connected. If anything fails it will
// // just erase the queue and try upload from scratch...
// class SyncManager {
//   static const int _uploadMaxBuffer = 10;
//   static const Duration _uploadInterval = Duration(milliseconds: 1000);
//   // for now, the server is polled every 5 seconds
//   static const Duration _downloadInterval = Duration(milliseconds: 5000);

//   final Uri _endpoint;
//   final RpcClient _rpcClient;
//   final EventStore _eventStore;

//   final StreamController<StoredEvent> _remoteEventController =
//       StreamController<StoredEvent>.broadcast();
//   Stream<StoredEvent> get remoteEventStream => _remoteEventController.stream;

//   final SyncStateManager _stateManager = SyncStateManager();
//   Stream<SyncState> get syncStateStream => _stateManager.stream;

//   final RetryStrategy _retryStrategy = RetryStrategyConstantBackoff(
//     duration: Duration(seconds: 3),
//   );

//   bool _enabled = false;

//   Timer? _reconnectTimer;
//   Timer? _uploadTimer;
//   Timer? _downloadTimer;

//   // latest uploaded event id... this is not needed
//   late EventVectorClock _uploadedEventClock;
//   // late Future<void> Function()? cancelConnectionStatusStream;

//   SyncManager(this._rpcClient, this._eventStore, this._endpoint) {
//     _rpcClient.connectionStatusStream.listen(_connectionStatusChanged);
//   }

//   void _connectionStatusChanged(RpcClientConnectionStatus status) {
//     final isConnected = status == RpcClientConnectionStatus.connected;

//     _stateManager.setConnected(isConnected);

//     // queue the download and upload
//     _downloadAndPoll();
//     _uploadStart();
//   }

//   // need automatic replication on/off...
//   // separate from connected/disconnected

//   void setEnabled(bool enable) {
//     final current = _enabled;
//     _enabled = enable;

//     assert(current != enable);

//     // this will enable/disable reconnect timer
//     // _startConnecting();
//     if (current == false && enable == true) {
//       // turn it on
//       _startConnecting();
//     } else if (current == true && enable == false) {
//       // shut it down
//       _reconnectTimer?.cancel();
//     }
//   }

//   // tries to reconnect indefinitely
//   void _startConnecting({connectAttempts = 0}) async {
//     // _reconnectTimer?.cancel();
//     if (_enabled == false) {
//       return;
//     }
//     // if already connected, do nothing instead?
//     assert(_rpcClient.connectionStatus != RpcClientConnectionStatus.connected);

//     final waitDuration = _retryStrategy.getTimeout(connectAttempts);

//     _reconnectTimer = Timer(waitDuration, () {
//       if (_enabled == false) {
//         return;
//       }
//       assert(
//         _rpcClient.connectionStatus != RpcClientConnectionStatus.connected,
//       );

//       _rpcClient.connect(_endpoint).catchError((_) {
//         _startConnecting(connectAttempts: connectAttempts + 1);
//       });
//     });
//   }

//   /// TODO: this must never be called, use the setEnabled() instead
//   Future<void> disconnect() async {
//     await _rpcClient.disconnect();
//   }

//   void dispose() {
//     // this should not do these, but assert that all these timers are cancelled
//     // already
//     _uploadTimer?.cancel();
//     _downloadTimer?.cancel();
//     _reconnectTimer?.cancel();
//     _remoteEventController.close();
//     _stateManager.dispose();
//   }

//   /// addEvent will serialize it to disk and perform network replication!
//   Future<void> addLocalEvent(StoredEvent event) async {
//     await _eventStore.storeEvent(event);

//     // queue this for sending
//   }

//   void _downloadAndPoll() async {
//     _downloadTimer?.cancel();

//     try {
//       await syncDownload();
//     } catch (e) {
//       // do nothing, the timer will be reset and download will be attempted again
//     }

//     _downloadTimer = Timer(_downloadInterval, () {
//       _downloadAndPoll();
//     });
//   }

//   // TODO: this could be super flaky
//   void _uploadStart() async {
//     _uploadTimer?.cancel();

//     if (!_stateManager.isUploading && _uploadPendingCount > _uploadMaxBuffer) {
//       await syncUpload();
//     }

//     _uploadTimer = Timer(_uploadInterval, () async {
//       if (_stateManager.isUploading) {
//         // just retry later?
//         _uploadStart();
//         return;
//       }

//       if (_uploadPendingCount > 0) {
//         await syncUpload();
//         _uploadStart(); // always retry after uploading
//       }
//     });
//   }

//   /// This function will perform full sync, aka push and pull events with remote
//   /// first it will upload all missing events, then download new ones.
//   ///
//   /// This is only used on the initial startup (or force resync) and can only be
//   /// performed when the sync manager is disabled? This will establish a new
//   /// connection, perform sync and then disconnect the connection
//   Future<bool> syncFull() async {
//     if (!_stateManager.isConnected) {
//       return false;
//     }

//     if (_stateManager.isDownloading || _stateManager.isUploading) {
//       throw StateError('SyncFull must be run uniquely');
//     }

//     final localClock = _eventStore.vectorClock;

//     // this can fail if the client

//     try {
//       final clockResult = await _rpcClient.queryClock(
//         _rpcClient.serverDeviceId(),
//       );
//       final remoteClock = clockResult.eventClock;

//       await _syncUpload(localClock, remoteClock);
//       // I dont think remote clock needs to be updated
//       await _syncDownload(localClock, remoteClock);

//       return true;
//     } catch (e) {
//       print('syncFull experienced error: $e');
//       return false;
//     }
//   }

//   Future<void> syncUpload() async {
//     if (!_stateManager.isConnected) {
//       throw StateError('Cannot upload when not connected');
//     }

//     final localClock = _eventStore.vectorClock;

//     final clockResult = await _rpcClient.queryClock(
//       _rpcClient.serverDeviceId(),
//     );
//     final remoteClock = clockResult.eventClock;

//     await _syncUpload(localClock, remoteClock);
//   }

//   Future<void> syncDownload() async {
//     if (!_stateManager.isConnected) {
//       throw StateError('Cannot download when not connected');
//     }

//     final localClock = _eventStore.vectorClock;

//     final clockResult = await _rpcClient.queryClock(
//       _rpcClient.serverDeviceId(),
//     );
//     final remoteClock = clockResult.eventClock;

//     await _syncDownload(localClock, remoteClock);
//   }

//   Future<void> _syncUpload(
//     EventVectorClock localClock,
//     EventVectorClock remoteClock,
//   ) async {
//     if (_stateManager.isUploading) {
//       throw StateError('Only single syncUpload should be ran concurrently');
//     }

//     final range = EventVectorClockRange.betweenClocks(remoteClock, localClock);
//     if (range.isEmpty) {
//       // no need to sync
//       return;
//     }

//     _stateManager.setUpload(true);
//     try {
//       while (range.isNotEmpty) {
//         final stream = _eventStore.getEvents(range, _uploadMaxBuffer);
//         final events = await stream.toList();

//         await _rpcClient.uploadEvents(
//           _rpcClient.serverDeviceId(),
//           ProtoMessageEventValue(events),
//         );

//         // advance ids only after the upload? or before?
//         for (final event in events) {
//           range.advanceById(event.id);
//           _uploadedEventClock.update(event.id);
//         }
//       }
//     } finally {
//       _stateManager.setUpload(false);
//     }
//   }

//   Future<void> _syncDownload(
//     EventVectorClock localClock,
//     EventVectorClock remoteClock,
//   ) async {
//     if (_stateManager.isDownloading) {
//       throw StateError('Only single syncDownload should be ran concurrently');
//     }

//     final range = EventVectorClockRange.betweenClocks(localClock, remoteClock);
//     if (range.isEmpty) {
//       return;
//     }

//     _stateManager.setDownload(true);
//     try {
//       while (range.isNotEmpty) {
//         final response = await _rpcClient.queryEvents(
//           _rpcClient.serverDeviceId(),
//           ProtoMessageEventQuery(range, _uploadMaxBuffer),
//         );
//         final events = response.events;

//         for (final event in events) {
//           // TODO: batch store
//           await _eventStore.storeEvent(event);
//           _remoteEventController.add(event);
//         }
//       }
//     } finally {
//       _stateManager.setDownload(false);
//     }
//   }
// }
