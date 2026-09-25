import 'dart:convert';

import 'package:crdt/crdt_text.dart';

CrdtTextChange save(CrdtText text) {
  final change = text.prepareChange()!;
  text.acknowledgeChange(change);
  return change;
}

Map<String, Object?> jsonCopy(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>();

CrdtTextId textId(int counter, [String actor = 'A']) =>
    CrdtTextId(actorId: actor, counter: counter);

CrdtTextInsert insertion(
  int counter, {
  String actor = 'A',
  Map<String, int> dependencies = const {},
  CrdtTextId? after,
  String character = 'x',
}) => CrdtTextInsert(
  id: textId(counter, actor),
  dependencies: dependencies,
  after: after,
  character: character,
);

final class FakeTextController implements CrdtTextController {
  CrdtTextEditingValue _value = CrdtTextEditingValue();
  final List<void Function()> listeners = [];
  int assignments = 0;

  @override
  CrdtTextEditingValue get value => _value;

  @override
  set value(CrdtTextEditingValue next) {
    assignments++;
    if (next == _value) return;
    _value = next;
    for (final listener in List.of(listeners)) {
      if (listeners.contains(listener)) listener();
    }
  }

  @override
  void addListener(void Function() listener) => listeners.add(listener);

  @override
  void removeListener(void Function() listener) => listeners.remove(listener);

  void edit(
    String text,
    int caret, {
    int? base,
    int composingStart = -1,
    int composingEnd = -1,
  }) {
    value = CrdtTextEditingValue(
      text: text,
      selectionBase: base ?? caret,
      selectionExtent: caret,
      composingStart: composingStart,
      composingEnd: composingEnd,
    );
  }
}
