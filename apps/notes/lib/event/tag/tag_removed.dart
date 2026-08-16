part of 'tag.dart';

class TagRemoved extends TagEvent {
  static const String type = 'tag.removed';

  const TagRemoved();

  @override
  Map<String, dynamic> toJson() {
    return {};
  }

  factory TagRemoved.fromJson(Map<String, dynamic> json) {
    return TagRemoved();
  }

  @override
  String toString() {
    return 'TagRemoved{}';
  }
}

final class TagRemovedCodec implements EventCodec<TagRemoved> {
  const TagRemovedCodec();

  @override
  String get kind => TagRemoved.type;

  @override
  Uint8List toBytes(TagRemoved event) => JsonConverter.encode(event.toJson());

  @override
  TagRemoved fromBytes(Uint8List bytes) =>
      TagRemoved.fromJson(JsonConverter.decode(bytes));
}
