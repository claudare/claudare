import 'package:flutter/foundation.dart';

class NoteOrderModel extends ChangeNotifier {
  List<String> notes = [];

  void addNote(String note) {
    notes.add(note);
    notifyListeners();
  }

  void removeNote(int index) {
    notes.removeAt(index);
    notifyListeners();
  }
}
