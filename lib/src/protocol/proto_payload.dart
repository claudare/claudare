// this is the communication protocol definition
// the server must be kept stateless. And every single client should be able
// to act as a server or as a client

import 'dart:typed_data';

import 'package:core/src/protocol/proto_headers.dart';
import 'package:core/src/protocol/proto_messages.dart';
import 'package:core/src/rpc_client/exceptions.dart';
import 'package:messagepack/messagepack.dart';

class ProtoPayload {
  final int version;
  final Map<int, ProtoAnyHeader> headers;
  final ProtoAnyMessage data;

  const ProtoPayload(this.headers, this.data, {this.version = 0});

  factory ProtoPayload.errorResponse(
    ProtoHeaderAck requestAck,
    String error, {
    required ProtoHeaderAuth auth,
  }) {
    final payload = ProtoPayload({}, ProtoMessageEmpty());

    final responseAck = ProtoHeaderAck(requestAck.payloadId, error);

    // auth is also needed
    payload.setHeader(auth);
    payload.setHeader(responseAck);

    return payload;
  }

  factory ProtoPayload.errorResponseWithStack(
    ProtoHeaderAck requestAck,
    Object originalError,
    StackTrace stackTrace, {
    required ProtoHeaderAuth auth,
  }) {
    final message = '$originalError; stack: \n$stackTrace';

    return ProtoPayload.errorResponse(requestAck, message, auth: auth);
  }

  void setHeader(ProtoAnyHeader header) {
    if (header is ProtoHeaderAuth) {
      headers[ProtoHeaderAuth.staticType] = header;
    } else if (header is ProtoHeaderAck) {
      headers[ProtoHeaderAck.staticType] = header;
    } else {
      throw Exception("Unknown header $header");
    }
  }

  T? _getHeader<T extends ProtoAnyHeader>(int value) {
    if (headers.isEmpty) {
      return null;
    }
    final header = headers[value];
    if (header == null) {
      return null;
    }
    return header as T;
  }

  ProtoHeaderAuth getAuth() {
    final result = _getHeader<ProtoHeaderAuth>(ProtoHeaderAuth.staticType);

    if (result == null) {
      throw RpcException('ProtoPayload is missing auth');
    }

    return result;
  }

  ProtoHeaderAck? getAck() {
    return _getHeader<ProtoHeaderAck>(ProtoHeaderAck.staticType);
  }

  ProtoHeaderForward? getForward() {
    return _getHeader<ProtoHeaderForward>(ProtoHeaderForward.staticType);
  }

  Uint8List pack() {
    final p = Packer();

    // TODO: append magic
    p.packInt(version);

    p.packMapLength(headers.length);
    for (final header in headers.values) {
      header.pack(p);
    }

    data.pack(p);

    return p.takeBytes();
  }

  // TODO: maybe add an unpack method which will provide header check function
  // this way, the rest of the messages can be ignored if headers are not good
  factory ProtoPayload.unpack(Uint8List bytes) {
    final u = Unpacker(bytes);
    final version = u.unpackInt();
    if (version == null || version != 0) {
      throw Exception('Unknown EventProto version $version, expected 0');
    }

    // headers
    final headerLen = u.unpackMapLength();
    final headers = <int, ProtoAnyHeader>{};
    for (var i = 0; i < headerLen; i++) {
      final val = ProtoAnyHeader.unpack(u);
      headers[val.type] = val;
    }

    final data = ProtoAnyMessage.unpack(u);

    return ProtoPayload(headers, data, version: version);
  }

  @override
  String toString() {
    return 'ProtoPayload{headers: $headers, body: $data}';
  }
}
