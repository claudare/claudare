import 'package:core/core.dart';
import 'package:core/src/protocol/proto_messages.dart';
import 'package:core/src/rpc_client/exceptions.dart';

typedef ServerHandlerFn =
    Future<ProtoAnyMessage?> Function(
      ProtoAnyMessage req,
      RequestContext reqCtx,
    );

class ServerContext {
  // EventStore
  // BlobStore
  // Other things too
}

/// information about the requester
/// may not be needed?
class RequestContext {
  DeviceId deviceId;

  RequestContext(this.deviceId);
}

class RpcServerHandler extends RpcServerEventHandlers {
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
          throw RpcException('request type ${req.runtimeType} not supported');
      }
    } on RpcException catch (e) {
      print('rpc server handler soft failure. $e');

      rethrow;
    } catch (e) {
      print('rpc server handler hard failure. $e');

      // TODO: should this also be wrapped as the rpc exeption?
      throw RpcException(e.toString());
    }
  }

  // client wants the event clock
  // throw when error happens
  @override
  Future<ProtoMessageClockValue> onClockQuery(
    ProtoMessageClockQuery req,
  ) async {
    throw UnimplementedError('TODO');
  }

  // client wants events
  @override
  Future<ProtoMessageEventValue> onEventQuery(
    ProtoMessageEventQuery req,
  ) async {
    throw UnimplementedError('TODO');
  }

  // client is uploading events
  @override
  Future<void> onEventValue(ProtoMessageEventValue req) async {
    throw UnimplementedError('TODO');
  }
}

// no need to do this? mocks are done directly
abstract class RpcServerEventHandlers {
  Future<ProtoMessageClockValue> onClockQuery(ProtoMessageClockQuery req);
  Future<ProtoMessageEventValue> onEventQuery(ProtoMessageEventQuery req);
  Future<void> onEventValue(ProtoMessageEventValue req) async {
    throw UnimplementedError('TODO');
  }
}
