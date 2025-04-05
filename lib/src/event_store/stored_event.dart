import 'dart:typed_data';

import 'package:core/src/event_store/id.dart';
import 'package:messagepack/messagepack.dart';

class StoredEvent {
  final EventId id;
  // maybe store a flag of weather this is encrypted or not.
  final Uint8List bytes;

  StoredEvent(this.id, this.bytes);

  void pack(Packer p) {
    id.pack(p);
    p.packBinary(bytes);
  }

  // unpacking is improved by applying patches from
  // https://github.com/nailgilaziev/messagepack/pull/9
  StoredEvent.unpack(Unpacker u)
    : id = EventId.unpack(u),
      bytes = Uint8List.fromList(u.unpackBinary());
}
