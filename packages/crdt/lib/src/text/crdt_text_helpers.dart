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
