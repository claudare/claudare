import 'package:core/core.dart';
import 'package:core/event_store.dart';
import 'package:core/src/blob_store/store.dart';
import 'package:core/src/protocol/proto_messages.dart';
import 'package:core/src/rpc_client/exceptions.dart';

class ServerContext {
  EventStore eventStore;
  BlobStore blobStore;

  ServerContext(this.eventStore, this.blobStore);
}

/// information about the requester
/// may not be needed?
class RequestContext {
  DeviceId deviceId;

  RequestContext(this.deviceId);
}

class RpcServerHandler {
  final ServerContext ctx;

  RpcServerHandler(this.ctx);

  Future<ProtoAnyMessage?> handle(
    ProtoAnyMessage req,
    RequestContext reqCtx,
  ) async {
    try {
      switch (req.runtimeType) {
        case const (ProtoMessagePing):
          return null;
        case ProtoMessageClockQuery data:
          return await onClockQuery(data);
        case ProtoMessageEventQuery data:
          return await onEventQuery(data);
        case ProtoMessageEventValue data:
          await onEventValue(data);
          return null;
        default:
          throw Exception('request type ${req.runtimeType} not supported');
      }
    } catch (e) {
      // print('rpc server handler failure. $e; stack: $stackTrace');

      throw RpcException(e.toString());
    }
  }

  // client wants the event clock
  // throw when error happens
  Future<ProtoMessageClockValue> onClockQuery(
    ProtoMessageClockQuery req,
  ) async {
    final vectorClock = ctx.eventStore.vectorClock;

    return ProtoMessageClockValue(vectorClock);
  }

  // client wants events
  Future<ProtoMessageEventValue> onEventQuery(
    ProtoMessageEventQuery req,
  ) async {
    final eventStream = ctx.eventStore.getEvents(req.cursor, req.limit);
    final eventList = await eventStream.toList();

    return ProtoMessageEventValue(eventList);
  }

  // client is uploading events
  Future<void> onEventValue(ProtoMessageEventValue req) async {
    for (final eventRaw in req.events) {
      // TODO: store many events at a time, while checking the clock?
      await ctx.eventStore.storeEvent(eventRaw);
    }
  }
}
