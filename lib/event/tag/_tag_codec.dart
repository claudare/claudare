import 'package:core/cqrs.dart';
import 'package:core/utils.dart';
import 'package:notes_app_v0/event/tag/tag.dart';

const tagCodec = TagCodec();

class TagCodec extends EventCodec<TagEvent> {
  const TagCodec();

  @override
  EncodedEvent encode(TagEvent event) {
    final bytes = JsonConverter.encode(event.toJson());
    switch (event) {
      case TagAssigned():
        return EncodedEvent(kind: TagAssigned.type, bytes: bytes);
      case TagCreated():
        return EncodedEvent(kind: TagCreated.type, bytes: bytes);
      case TagRenamed():
        return EncodedEvent(kind: TagRenamed.type, bytes: bytes);
      case TagUnassigned():
        return EncodedEvent(kind: TagUnassigned.type, bytes: bytes);
      case TagRemoved():
        return EncodedEvent(kind: TagRemoved.type, bytes: bytes);
    }
  }

  @override
  TagEvent decode(EncodedEvent encoded) {
    final detailMap = JsonConverter.decode(encoded.bytes);

    switch (encoded.kind) {
      case TagAssigned.type:
        return TagAssigned.fromJson(detailMap);
      case TagCreated.type:
        return TagCreated.fromJson(detailMap);
      case TagRenamed.type:
        return TagRenamed.fromJson(detailMap);
      case TagUnassigned.type:
        return TagUnassigned.fromJson(detailMap);
      case TagRemoved.type:
        return TagRemoved.fromJson(detailMap);
      default:
        throw UnsupportedError('Unknown tag event type: ${encoded.kind}');
    }
  }
}
