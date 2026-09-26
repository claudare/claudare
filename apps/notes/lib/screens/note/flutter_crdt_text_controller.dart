import 'package:crdt/crdt_text.dart';
import 'package:flutter/widgets.dart';

/// Adapts Flutter editing values for [CrdtTextBinding].
class FlutterCrdtTextController implements CrdtTextController {
  final TextEditingController controller;

  FlutterCrdtTextController(this.controller);

  @override
  CrdtTextEditingValue get value {
    final value = controller.value;
    return CrdtTextEditingValue(
      text: value.text,
      selectionBase: value.selection.baseOffset,
      selectionExtent: value.selection.extentOffset,
      affinity:
          value.selection.affinity == TextAffinity.upstream
              ? CrdtTextAffinity.upstream
              : CrdtTextAffinity.downstream,
      isDirectional: value.selection.isDirectional,
      composingStart: value.composing.start,
      composingEnd: value.composing.end,
    );
  }

  @override
  set value(CrdtTextEditingValue value) {
    controller.value = TextEditingValue(
      text: value.text,
      selection: TextSelection(
        baseOffset: value.selectionBase,
        extentOffset: value.selectionExtent,
        affinity:
            value.affinity == CrdtTextAffinity.upstream
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
