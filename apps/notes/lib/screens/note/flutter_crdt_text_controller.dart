import 'package:crdt/crdt_text.dart' as crdt;
import 'package:flutter/widgets.dart';

/// Adapts Flutter editing values for [crdt.CrdtTextBinding].
class FlutterCrdtTextController implements crdt.CrdtTextController {
  final TextEditingController controller;

  FlutterCrdtTextController(this.controller);

  @override
  crdt.TextEditingValue get value {
    final value = controller.value;
    return crdt.TextEditingValue(
      text: value.text,
      selectionBase: value.selection.baseOffset,
      selectionExtent: value.selection.extentOffset,
      affinity:
          value.selection.affinity == TextAffinity.upstream
              ? crdt.TextAffinity.upstream
              : crdt.TextAffinity.downstream,
      isDirectional: value.selection.isDirectional,
      composingStart: value.composing.start,
      composingEnd: value.composing.end,
    );
  }

  @override
  set value(crdt.TextEditingValue value) {
    controller.value = TextEditingValue(
      text: value.text,
      selection: TextSelection(
        baseOffset: value.selectionBase,
        extentOffset: value.selectionExtent,
        affinity:
            value.affinity == crdt.TextAffinity.upstream
                ? TextAffinity.upstream
                : TextAffinity.downstream,
        isDirectional: value.isDirectional,
      ),
      composing: TextRange(
        start: value.composingStart,
        end: value.composingEnd,
      ),
    );
  }

  @override
  void addListener(void Function() listener) =>
      controller.addListener(listener);

  @override
  void removeListener(void Function() listener) =>
      controller.removeListener(listener);
}
