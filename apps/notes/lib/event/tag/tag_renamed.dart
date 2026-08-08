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
