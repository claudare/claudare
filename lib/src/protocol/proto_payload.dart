// this is the communication protocol definition
// the server must be kept stateless. And every single client should be able
// to act as a server or as a client

import 'dart:typed_data';

import 'package:core/src/protocol/proto_headers.dart';
import 'package:core/src/protocol/proto_messages.dart';
import 'package:messagepack/messagepack.dart';

class ProtoPayload {
  int version;
  // the headers must be stored by the type ids?
  List<ProtoAnyHeader> headers;
  List<ProtoAnyMessage> messages;

  ProtoPayload(this.headers, this.messages, {this.version = 0});

  Uint8List pack() {
    final p = Packer();

    // TODO: append magic
    p.packInt(version);

    p.packListLength(headers.length);
    for (final header in headers) {
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
    final headerLen = u.unpackListLength();
    final headers = List<ProtoAnyHeader>.generate(
      headerLen,
      (_) => ProtoAnyHeader.unpack(u),
      growable: false,
    );

    // messages
    final messageLen = u.unpackListLength();
    final messages = List<ProtoAnyMessage>.generate(
      messageLen,
      (_) => ProtoAnyMessage.unpack(u),
      growable: false,
    );

    return ProtoPayload(headers, messages, version: version);
  }
}
