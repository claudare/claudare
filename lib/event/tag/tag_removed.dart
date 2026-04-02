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
