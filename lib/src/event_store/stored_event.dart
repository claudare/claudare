import 'dart:typed_data';

import 'package:core/src/event_store/id.dart';
import 'package:messagepack/messagepack.dart';

class StoredEvent {
  final EventId id;
  final String data; // this must be string, as json does not allow binaries

  StoredEvent(this.id, this.data);

  StoredEvent.fromJson(Map<String, dynamic> json)
    : id = EventId.fromString(json['id']),
      data = json['data'];

  Map<String, dynamic> toJson() => {'id': id.toString(), 'data': data};
}

class StoredEventBinary {
  final EventId id;
  // maybe store a flag of weather this is encrypted or not.
  final Uint8List cypherBytes;

  StoredEventBinary(this.id, this.cypherBytes);

  void pack(Packer p) {
    id.pack(p);
    p.packBinary(cypherBytes);
  }

  // unpacking is improved by applying patches from
  // https://github.com/nailgilaziev/messagepack/pull/9
  StoredEventBinary.unpack(Unpacker u)
    : id = EventId.unpack(u),
      cypherBytes = Uint8List.fromList(u.unpackBinary());
}
