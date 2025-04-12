import 'dart:async';
import 'dart:collection';

import 'package:core/core.dart';
import 'package:core/device_keychain.dart';
import 'package:core/protocol.dart';
import 'package:core/src/event_store/id.dart';
import 'package:core/src/event_store/stored_event.dart';
import 'package:core/src/event_store/vector_clock.dart';
import 'package:core/src/net_connection.dart';

// this is basically the database abstraction
abstract class EventSyncContext {
  List<StoredEvent> getLocalEvents(EventVectorClock cursor, int limit);
  Future<void> saveLocalEvent(StoredEvent event);
}

class _AckData {
  final int payloadId;
  final EventId eventId;

  const _AckData(this.payloadId, this.eventId);
}

class _MirroredExchange<T extends ProtoAnyMessage> {
  int step = 0;
  int? ackId;
  final Future<void> Function(int payloadId, T message) checkFn;

  _MirroredExchange(this.checkFn);

  bool get done => step == 2;

  // returns true if we are done
  Future<bool> handle(ProtoPayload payload) async {
    final message = payload.data;

    if (message is ProtoMessageAck) {
      if (ackId == null) {
        throw Exception(
          'Failed to mirror exchange ${T.runtimeType}: no ackId for ${message.payloadId}',
        );
      }
      if (message.payloadId != ackId!) {
        throw Exception(
          'Failed to mirror exchange ${T.runtimeType}: expected ack $ackId, got ${message.payloadId}',
        );
      }
      if (message.error.isNotEmpty) {
        throw Exception(
          'Failed to mirror exchange ${T.runtimeType}: ack error: ${message.error}',
        );
      }

      ackId = null;
      step++;
    } else if (message is T) {
      try {
        await checkFn(payload.id, message);
        step++;
      } catch (err) {
        rethrow;
      }
    } else {
      throw Exception(
        'Failed to mirror exchange ${T.runtimeType}, got ${message.runtimeType} message',
      );
    }

    return done;
  }
}

// [EventSync] implemenets common logic that deals with replication of events
// and their serialization. [EventSync] lives as long as the connection is
// alive. When it disconnects, the EventSync needs to be rebuilt from scratch.
class EventSync {
  final EventSyncContext context;
  final NetConnection connection;
  final bool isClient;
  final DeviceKeychain deviceKeychain;
  final DeviceId peerDeviceId;

  int _nextPayloadId = 0;

  final _readyCompleter = Completer<void>();

  // internal testing for robustness
  late _MirroredExchange<ProtoMessageAuth> authExchange;
  late _MirroredExchange<ProtoMessageClockValue> clockExchange;

  final eventAckQueue = Queue<_AckData>();

  final EventVectorClock localVC;
  // final EventVectorClock? peerPendingVC; // latest event id of the pending
  EventVectorClock? peerVC;

  EventSync(
    this.context,
    this.connection, {
    required this.isClient,
    required this.deviceKeychain,
    required this.peerDeviceId,
    // ensure a COPY of the clock is passed
    required EventVectorClock localVC,
  }) : localVC = localVC.clone() {
    authExchange = _MirroredExchange<ProtoMessageAuth>(_checkAuth);
    clockExchange = _MirroredExchange<ProtoMessageClockValue>(_clockExchangeDo);
  }

  void newEvent(StoredEvent event) {
    if (peerVC == null) {
      localVC.update(event.id);
      return;
    }

    if (peerVC != localVC) {
      localVC.update(event.id);
      return;
    }

    localVC.update(event.id);
    // peerVC!.update(event.id);

    // this needs to
    final payloadId = _sendMessage(ProtoMessageEventValue(event));
    eventAckQueue.add(_AckData(payloadId, event.id));
  }

  // start needs to be called, it will return when initialization is complte
  Future<void> start() {
    deviceKeychain
        .makeClaim(peerDeviceId)
        .then((claim) {
          authExchange.ackId = _sendMessage(ProtoMessageAuth(claim));
          return null;
        })
        .catchError((err) {
          print('Failed to make claim: $err');
          // close the connection somehow...
        });

    connection.stream.listen(
      (data) async {
        try {
          final payload = ProtoPayload.fromBytes(data);

          if (!authExchange.done) {
            final done = await authExchange.handle(payload);
            if (done) {
              // send the clock exchange message
              clockExchange.ackId = _sendMessage(
                ProtoMessageClockValue(localVC),
              );
            }
            return;
          } else if (!clockExchange.done) {
            final done = await clockExchange.handle(payload);
            if (done) {
              _readyCompleter.complete();
            }
            return;
          }

          if (payload.data is ProtoMessagePing) {
            _sendMessage(ProtoMessageAck(payload.id, ""));
            return;
          }

          _doEventHandling(payload);
        } catch (err) {
          print('Error processing data: $err');
          rethrow;
        }
      },
      onError: (err) {
        if (!authExchange.done || !clockExchange.done) {
          _readyCompleter.completeError(err);
        }

        print('EventSync processing failure: $err');
      },
    );

    return _readyCompleter.future;
  }

  void _doEventHandling(ProtoPayload payload) {
    assert(peerVC != null);

    final message = payload.data;
    if (message is ProtoMessageAck) {
      // handle acks for the remote... they will increment the remote clock
      // peerVC!.update
      // _sendMessage(ProtoMessageAck(payload.id, ""));
    } else if (message is ProtoMessageEventValue) {
      context
          .saveLocalEvent(message.event)
          .then((_) {
            // ack on success
            _sendMessage(ProtoMessageAck(payload.id, ""));
          })
          .catchError((err) {
            // ack error on error
            _sendMessage(ProtoMessageAck(payload.id, err.toString()));
            throw Exception('what will this do?');
          });
    } else {
      throw Exception('Unexpected event type ${payload.data.runtimeType}');
    }
  }

  Future<void> _checkAuth(int payloadId, ProtoMessageAuth message) async {
    await deviceKeychain.checkClaim(message.claim);
    _sendMessage(ProtoMessageAck(payloadId, ""));
  }

  Future<void> _clockExchangeDo(
    int payloadId,
    ProtoMessageClockValue message,
  ) async {
    peerVC = message.eventClock;
    _sendMessage(ProtoMessageAck(payloadId, ""));
  }

  int _sendMessage(ProtoAnyMessage data) {
    final payloadId = _nextPayloadId;
    _nextPayloadId++;

    final payload = ProtoPayload(payloadId, data);
    final payloadBytes = payload.toBytes();
    connection.sink.add(payloadBytes);

    return payloadId;
  }
}
