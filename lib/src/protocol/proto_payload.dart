// this is the communication protocol definition
// the server must be kept stateless. And every single client should be able
// to act as a server or as a client

import 'dart:typed_data';

import 'package:core/src/protocol/proto_headers.dart';
import 'package:core/src/protocol/proto_messages.dart';
import 'package:messagepack/messagepack.dart';

class ProtoPayload {
  final int version;
  final Map<int, ProtoAnyHeader> headers;
  final ProtoAnyMessage data;

  const ProtoPayload(this.headers, this.data, {this.version = 0});

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

  ProtoHeaderAuth? getAuth() {
    return _getHeader<ProtoHeaderAuth>(ProtoHeaderAuth.staticType);
  }

  ProtoHeaderAck? getAck() {
    return _getHeader<ProtoHeaderAck>(ProtoHeaderAck.staticType);
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
}
