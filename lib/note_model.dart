import 'package:flutter/cupertino.dart';
import 'package:notes_app_v0/common.dart';

class NoteModel extends ChangeNotifier {
  final Id noteId;
  String _title;
  String _body;
  final Set<String> _tags;

  NoteModel(
    this.noteId, {
    String title = '',
    String body = '',
    Set<String> tags = const {},
  }) : _tags = tags,
       _body = body,
       _title = title;

  String get title => _title;
  void updateTitle(String newTitle) {
    _title = newTitle;
    notifyListeners();
  }

  String get body => _body;
  void updateBody(String newBody) {
    _body = newBody;
    notifyListeners();
  }

  Set<String> get tags => _tags;
  void addTag(String newTag) {
    _tags.add(newTag);
    notifyListeners();
  }

  void removeTag(String tagToRemove) {
    _tags.remove(tagToRemove);
    notifyListeners();
  }

  @override
  String toString() {
    final tagStr = _tags.isEmpty ? 'none' : _tags.join(', ');
    return 'Note[id: $noteId, title: $_title, body: $_body, tags: $tagStr]';
  }
}
