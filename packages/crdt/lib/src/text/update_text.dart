import 'crdt_text.dart';

/// Updates [context] to [newText] through one [CrdtTextEditContext.replace] call.
///
/// Preserves the common Unicode scalar prefix and suffix. [newText] describes
/// the desired complete draft; identical text produces no change.
void updateText(CrdtTextEditContext context, String newText) {
  final previous = context.text;
  if (previous == newText) return;

  final oldScalars = previous.runes.toList();
  final newScalars = newText.runes.toList();
  var prefix = 0;
  var start = 0;
  while (prefix < oldScalars.length &&
      prefix < newScalars.length &&
      oldScalars[prefix] == newScalars[prefix]) {
    start += oldScalars[prefix] > 0xffff ? 2 : 1;
    prefix++;
  }

  var suffix = 0;
  var tailLength = 0;
  while (suffix < oldScalars.length - prefix &&
      suffix < newScalars.length - prefix &&
      oldScalars[oldScalars.length - suffix - 1] ==
          newScalars[newScalars.length - suffix - 1]) {
    tailLength += oldScalars[oldScalars.length - suffix - 1] > 0xffff ? 2 : 1;
    suffix++;
  }

  context.replace(
    start,
    previous.length - tailLength,
    newText.substring(start, newText.length - tailLength),
  );
}
