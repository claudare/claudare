/// Splits valid UTF-16 text into Unicode scalar strings.
List<String> unicodeScalars(String text) {
  final result = <String>[];
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= text.length) {
        throw ArgumentError('Text contains an unpaired surrogate.');
      }
      final next = text.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) {
        throw ArgumentError('Text contains an unpaired surrogate.');
      }
      result.add(text.substring(index, index + 2));
      index++;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw ArgumentError('Text contains an unpaired surrogate.');
    } else {
      result.add(text.substring(index, index + 1));
    }
  }
  return result;
}
