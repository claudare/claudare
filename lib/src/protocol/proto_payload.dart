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
  final List<ProtoAnyMessage> messages;

  const ProtoPayload(this.headers, this.messages, {this.version = 0});

  ProtoHeaderAuth? getAuth() {
    if (headers.isEmpty) {
      return null;
    }
    final header = headers[ProtoHeaderAuth.staticType];
    if (header == null) {
      return null;
    }
    return header as ProtoHeaderAuth;
  }

  ProtoHeaderAck? getAck() {
    if (headers.isEmpty) {
      return null;
    }
    final header = headers[ProtoHeaderAck.staticType];
    if (header == null) {
      return null;
    }
    return header as ProtoHeaderAck;
  }

  Uint8List pack() {
    final p = Packer();

    // TODO: append magic
    p.packInt(version);

    p.packMapLength(headers.length);
    for (final header in headers.values) {
      header.pack(p);
    }

    p.packListLength(messages.length);
    for (final message in messages) {
      message.pack(p);
    }

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

    final messageLen = u.unpackListLength();
    final messages = List<ProtoAnyMessage>.generate(
      messageLen,
      (_) => ProtoAnyMessage.unpack(u),
      growable: false,
    );

    return ProtoPayload(headers, messages, version: version);
  }
}
