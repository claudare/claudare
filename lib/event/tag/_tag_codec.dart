import 'dart:convert';

import 'package:core/cqrs.dart';
import 'package:notes_app_v0/event/tag/tag.dart';

const tagCodec = TagCodec();

class TagCodec extends EventCodec<TagEvent> {
  const TagCodec();

  @override
  EncodedEvent encode(TagEvent event) {
    final detail = jsonEncode(event.toJson());
    switch (event) {
      case TagAssigned():
        return EncodedEvent(kind: TagAssigned.type, detail: detail);
      case TagCreated():
        return EncodedEvent(kind: TagCreated.type, detail: detail);
      case TagRenamed():
        return EncodedEvent(kind: TagRenamed.type, detail: detail);
      case TagUnassigned():
        return EncodedEvent(kind: TagUnassigned.type, detail: detail);
      case TagRemoved():
        return EncodedEvent(kind: TagRemoved.type, detail: detail);
    }
  }

  @override
  TagEvent decode(EncodedEvent encoded) {
    switch (encoded.kind) {
      case TagAssigned.type:
        return TagAssigned.fromJson(jsonDecode(encoded.detail));
      case TagCreated.type:
        return TagCreated.fromJson(jsonDecode(encoded.detail));
      case TagRenamed.type:
        return TagRenamed.fromJson(jsonDecode(encoded.detail));
      case TagUnassigned.type:
        return TagUnassigned.fromJson(jsonDecode(encoded.detail));
      case TagRemoved.type:
        return TagRemoved.fromJson(jsonDecode(encoded.detail));
      default:
        throw UnsupportedError('Unknown tag event type: ${encoded.kind}');
    }
  }
}
