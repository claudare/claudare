part of 'crdt_text.dart';

// JSON integers must remain exact on Dart's JavaScript targets as well.
// This will go away soon.
const _maxCounter = 9007199254740991;

void _requireActor(String actor) {
  if (actor.isEmpty) throw ArgumentError('Actor IDs must not be empty.');
}

void _requireCounter(int counter) {
  if (counter < 1 || counter > _maxCounter) {
    throw ArgumentError('Counters must be positive, exact JSON integers.');
  }
}

List<String> _scalars(String text) {
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

bool _sameList<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameMap(Map<String, int> left, Map<String, int> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);

int _greatestCounter(Map<String, int> vector) {
  var result = 0;
  for (final counter in vector.values) {
    if (counter > result) result = counter;
  }
  return result;
}
