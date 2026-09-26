import 'package:crdt/src/common/unicode_scalars.dart';

/// Visual caret affinity, independent of CRDT insertion ordering.
enum TextAffinity { upstream, downstream }

/// The editor's text, UTF-16 selection, and provisional composing range.
///
/// A negative selection offset means no selection. An absent composing range
/// uses -1 for both endpoints. Text must contain valid Unicode scalars.
final class TextEditingValue {
  final String text;
  final int selectionBase;
  final int selectionExtent;
  final TextAffinity affinity;
  final bool isDirectional;
  final int composingStart;
  final int composingEnd;

  TextEditingValue({
    this.text = '',
    this.selectionBase = -1,
    this.selectionExtent = -1,
    this.affinity = TextAffinity.downstream,
    this.isDirectional = false,
    this.composingStart = -1,
    this.composingEnd = -1,
  }) {
    unicodeScalars(text);
    RangeError.checkValueInInterval(
      selectionBase,
      -1,
      text.length,
      'selectionBase',
    );
    RangeError.checkValueInInterval(
      selectionExtent,
      -1,
      text.length,
      'selectionExtent',
    );
    if (composingStart != -1 || composingEnd != -1) {
      RangeError.checkValidRange(composingStart, composingEnd, text.length);
    }
  }

  bool get hasSelection => selectionBase >= 0 && selectionExtent >= 0;

  bool get isComposing => composingStart >= 0 && composingEnd > composingStart;

  TextEditingValue copyWith({
    String? text,
    int? selectionBase,
    int? selectionExtent,
    TextAffinity? affinity,
    bool? isDirectional,
    int? composingStart,
    int? composingEnd,
  }) => TextEditingValue(
    text: text ?? this.text,
    selectionBase: selectionBase ?? this.selectionBase,
    selectionExtent: selectionExtent ?? this.selectionExtent,
    affinity: affinity ?? this.affinity,
    isDirectional: isDirectional ?? this.isDirectional,
    composingStart: composingStart ?? this.composingStart,
    composingEnd: composingEnd ?? this.composingEnd,
  );

  @override
  bool operator ==(Object other) =>
      other is TextEditingValue &&
      text == other.text &&
      selectionBase == other.selectionBase &&
      selectionExtent == other.selectionExtent &&
      affinity == other.affinity &&
      isDirectional == other.isDirectional &&
      composingStart == other.composingStart &&
      composingEnd == other.composingEnd;

  @override
  int get hashCode => Object.hash(
    text,
    selectionBase,
    selectionExtent,
    affinity,
    isDirectional,
    composingStart,
    composingEnd,
  );
}
