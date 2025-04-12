import 'dart:typed_data';

import 'package:core/src/protocol/proto_messages.dart';
import 'package:messagepack/messagepack.dart';

class ProtoPayload {
  final int id;
  final ProtoAnyMessage data;

  const ProtoPayload(this.id, this.data);

  Uint8List toBytes() {
    final p = Packer();

    p.packInt(id);
    data.pack(p);

    return p.takeBytes();
  }

  factory ProtoPayload.fromBytes(Uint8List bytes) {
    final u = Unpacker(bytes);

    final msgId = u.unpackInt()!;
    final data = ProtoAnyMessage.unpack(u);

    return ProtoPayload(msgId, data);
  }

  @override
  String toString() {
    return 'ProtoPayload{id: $id, data: $data}';
  }
}
