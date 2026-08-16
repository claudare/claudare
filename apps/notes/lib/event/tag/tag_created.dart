part of 'tag.dart';

class TagCreated extends TagEvent {
  static const String type = 'tag.created';

  final String name;

  const TagCreated({required this.name});

  @override
  Map<String, dynamic> toJson() {
    return {'name': name};
  }

  factory TagCreated.fromJson(Map<String, dynamic> json) {
    return TagCreated(name: json['name'] as String);
  }

  @override
  String toString() {
    return 'TagCreated{name: $name}';
  }
}

final class TagCreatedCodec implements EventCodec<TagCreated> {
  const TagCreatedCodec();

  @override
  String get kind => TagCreated.type;

  @override
  Uint8List toBytes(TagCreated event) => JsonConverter.encode(event.toJson());

  @override
  TagCreated fromBytes(Uint8List bytes) =>
      TagCreated.fromJson(JsonConverter.decode(bytes));
}
