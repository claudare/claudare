part of 'crdt_text.dart';

/// Connects an editing draft to an editor without depending on its UI framework.
///
/// The draft initializes the editor. During IME composition, draft edits
/// still apply, but editor refreshes wait until composition ends. Local edits
/// target the displayed character IDs even while remote edits are undisplayed.
final class CrdtTextBinding {
  final CrdtTextEditContext _editContext;
  final CrdtTextController _controller;
  late List<CrdtTextInsert> _displayed;
  late CrdtTextEditingValue _value;
  bool _writingController = false;
  bool _handlingController = false;
  bool _disposed = false;

  CrdtTextBinding({
    required CrdtTextEditContext editContext,
    required CrdtTextController controller,
  }) : _editContext = editContext,
       _controller = controller {
    _displayed = editContext._draft._visibleAtoms();
    final content = _displayed.map((atom) => atom.character).join();
    _value = CrdtTextEditingValue(
      text: content,
      selectionBase: content.length,
      selectionExtent: content.length,
    );
    controller.value = _value;
    controller.addListener(_onControllerChange);
    _editContext.addListener(_onDocumentChange);
  }

  CrdtText get _text => _editContext._draft;

  /// Detaches listeners without disposing the supplied controller or context.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_onControllerChange);
    _editContext.removeListener(_onDocumentChange);
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
      if (next.text != _value.text) {
        final splice = _findSplice(_value, next);
        final inserted = _editContext._replaceIds(
          _displayed
              .sublist(splice.start, splice.end)
              .map((atom) => atom.id)
              .toList(),
          splice.start == 0 ? null : _displayed[splice.start - 1].id,
          splice.replacement,
        );
        _displayed = [
          ..._displayed.take(splice.start),
          ...inserted,
          ..._displayed.skip(splice.end),
        ];
      }
      _value = next;
      if (!_value.isComposing) _refreshEditor();
    } finally {
      _handlingController = false;
    }
  }

  void _onDocumentChange() {
    if (_disposed || _handlingController || _value.isComposing) return;
    _refreshEditor();
  }

  void _refreshEditor() {
    var base = -1;
    var extent = -1;
    if (_value.hasSelection) {
      final forward = _value.selectionBase <= _value.selectionExtent;
      final collapsed = _value.selectionBase == _value.selectionExtent;
      base = _resolve(
        _anchor(
          _value.selectionBase,
          stickAfterInsertions: collapsed || forward,
        ),
      );
      extent = _resolve(
        _anchor(
          _value.selectionExtent,
          stickAfterInsertions: collapsed || !forward,
        ),
      );
    }
    final composing = _value.composingStart < 0
        ? -1
        : _resolve(_anchor(_value.composingStart, stickAfterInsertions: true));
    _displayed = _text._visibleAtoms();
    final next = CrdtTextEditingValue(
      text: _displayed.map((atom) => atom.character).join(),
      selectionBase: base,
      selectionExtent: extent,
      affinity: _value.affinity,
      isDirectional: _value.isDirectional,
      composingStart: composing,
      composingEnd: composing,
    );
    _value = next;
    if (_controller.value == next) return;
    _writingController = true;
    try {
      _controller.value = next;
    } finally {
      _writingController = false;
    }
  }

  _TextAnchor _anchor(int offset, {required bool stickAfterInsertions}) {
    var position = 0;
    for (var index = 0; index < _displayed.length; index++) {
      final atom = _displayed[index];
      if (position == offset) {
        if (stickAfterInsertions) return _TextAnchor(atom.id, after: false);
        return index == 0
            ? const _TextAnchor(null, after: false)
            : _TextAnchor(_displayed[index - 1].id, after: true);
      }
      final end = position + atom.character.length;
      if (offset < end) {
        return _TextAnchor(atom.id, after: false, inset: offset - position);
      }
      position = end;
    }
    if (stickAfterInsertions) return const _TextAnchor(null, after: true);
    return _displayed.isEmpty
        ? const _TextAnchor(null, after: false)
        : _TextAnchor(_displayed.last.id, after: true);
  }

  int _resolve(_TextAnchor anchor) {
    if (anchor.id == null) return anchor.after ? _text.length : 0;
    final deleted = _text._deletedIds();
    var offset = 0;
    for (final atom in _text._orderedAtoms()) {
      final width = deleted.contains(atom.id) ? 0 : atom.character.length;
      if (atom.id == anchor.id) {
        return offset +
            (anchor.after ? width : (width == 0 ? 0 : anchor.inset));
      }
      offset += width;
    }
    throw StateError('The editor anchor is missing from its document.');
  }
}

final class _TextAnchor {
  final CrdtTextId? id;
  final bool after;
  final int inset;

  const _TextAnchor(this.id, {required this.after, this.inset = 0});
}

final class _TextSplice {
  final int start;
  final int end;
  final String replacement;

  const _TextSplice(this.start, this.end, this.replacement);
}

_TextSplice _findSplice(
  CrdtTextEditingValue previous,
  CrdtTextEditingValue next,
) {
  final old = _scalars(previous.text);
  final updated = _scalars(next.text);
  final commonLength = old.length < updated.length
      ? old.length
      : updated.length;
  var prefix = 0;
  while (prefix < commonLength && old[prefix] == updated[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < commonLength &&
      old[old.length - suffix - 1] == updated[updated.length - suffix - 1]) {
    suffix++;
  }
  final matched = prefix + suffix < commonLength
      ? prefix + suffix
      : commonLength;
  final earliest = matched > suffix ? matched - suffix : 0;
  final latest = prefix < matched ? prefix : matched;
  final oldOffsets = _scalarOffsets(old);
  final newOffsets = _scalarOffsets(updated);
  var chosen = latest;
  var bestScore = 3;
  // Several minimal splices can describe repeated text. Prefer the splice
  // consistent with the user's selection and resulting caret.
  for (var start = latest; start >= earliest; start--) {
    final tail = matched - start;
    final oldEnd = old.length - tail;
    final newEnd = updated.length - tail;
    var score = 3;
    if (next.hasSelection &&
        next.selectionBase == next.selectionExtent &&
        next.selectionExtent == newOffsets[newEnd]) {
      score = 2;
      if (previous.hasSelection) {
        final low = previous.selectionBase < previous.selectionExtent
            ? previous.selectionBase
            : previous.selectionExtent;
        final high = previous.selectionBase > previous.selectionExtent
            ? previous.selectionBase
            : previous.selectionExtent;
        if (low == oldOffsets[start] && high == oldOffsets[oldEnd]) {
          score = 0;
        } else if (low == high &&
            low >= oldOffsets[start] &&
            low <= oldOffsets[oldEnd]) {
          score = 1;
        }
      }
    }
    if (score < bestScore) {
      bestScore = score;
      chosen = start;
    }
  }
  final tail = matched - chosen;
  return _TextSplice(
    chosen,
    old.length - tail,
    updated.sublist(chosen, updated.length - tail).join(),
  );
}

List<int> _scalarOffsets(List<String> scalars) {
  final offsets = [0];
  for (final scalar in scalars) {
    offsets.add(offsets.last + scalar.length);
  }
  return offsets;
}
