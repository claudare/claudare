import 'package:crdt/src/string/crdt_string_edit_context.dart';
import 'package:crdt/src/text/crdt_text.dart';
import 'package:crdt/src/common/text_editing_value.dart';

/// Connects a string draft to an editor using the shared text adapter.
///
/// Remote replacements clamp selection offsets to the new string length.
/// Editor refreshes wait for active IME composition to finish.
final class CrdtStringBinding {
  final CrdtStringEditContext _editContext;
  final CrdtTextController _controller;
  late TextEditingValue _value;
  bool _writingController = false;
  bool _handlingController = false;
  bool _disposed = false;

  CrdtStringBinding({
    required CrdtStringEditContext editContext,
    required CrdtTextController controller,
  }) : _editContext = editContext,
       _controller = controller {
    _value = TextEditingValue(
      text: editContext.value,
      selectionBase: editContext.value.length,
      selectionExtent: editContext.value.length,
    );
    controller.value = _value;
    controller.addListener(_onControllerChange);
    editContext.addListener(_onDraftChange);
  }

  void _onControllerChange() {
    if (_disposed || _writingController) return;
    if (_handlingController) {
      throw StateError('Reentrant editor changes are not supported.');
    }
    final next = _controller.value;
    if (next == _value) return;
    _handlingController = true;
    try {
      if (next.text != _value.text) _editContext.value = next.text;
      _value = next;
      if (!next.isComposing) _refreshEditor();
    } finally {
      _handlingController = false;
    }
  }

  void _onDraftChange() {
    if (_disposed || _handlingController || _value.isComposing) return;
    _refreshEditor();
  }

  void _refreshEditor() {
    final text = _editContext.value;
    if (text == _value.text) return;
    final next = TextEditingValue(
      text: text,
      selectionBase: _value.selectionBase.clamp(-1, text.length),
      selectionExtent: _value.selectionExtent.clamp(-1, text.length),
      affinity: _value.affinity,
      isDirectional: _value.isDirectional,
    );
    _writingController = true;
    try {
      _controller.value = next;
      _value = next;
    } finally {
      _writingController = false;
    }
  }

  /// Detaches listeners without disposing the supplied context or controller.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_onControllerChange);
    _editContext.removeListener(_onDraftChange);
  }
}
