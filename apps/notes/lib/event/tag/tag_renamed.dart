part of 'tag.dart';

class TagRenamed extends TagEvent {
  static const String type = 'tag.renamed';

  final String newName;

  const TagRenamed({required this.newName});

  @override
  Map<String, dynamic> toJson() {
    return {'newName': newName};
  }

  factory TagRenamed.fromJson(Map<String, dynamic> json) {
    return TagRenamed(newName: json['newName'] as String);
  }

  @override
  String toString() {
    return 'TagRenamed{newName: $newName}';
  }
}

final class TagRenamedCodec implements EventCodec<TagRenamed> {
  const TagRenamedCodec();

  @override
  String get kind => TagRenamed.type;

  @override
  Uint8List toBytes(TagRenamed event) => JsonConverter.encode(event.toJson());

  @override
  TagRenamed fromBytes(Uint8List bytes) =>
      TagRenamed.fromJson(JsonConverter.decode(bytes));
}
