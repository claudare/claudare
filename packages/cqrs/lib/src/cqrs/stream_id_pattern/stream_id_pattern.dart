import 'package:cqrs/src/cqrs/pattern_filter.dart';

abstract class StreamIdPattern<TData> {
  const StreamIdPattern();

  String get pattern;
  PatternFilter get filter;

  TData toData(String path);
  String toPath(TData data);

  /// Returns true if this definition globs (covers) the other.
  /// e.g. "account/*" globs "account/123" → true
  /// e.g. "doc/*" globs "account/123"     → false
  /// e.g. "*" globs "account/123"         → true
  bool globs(StreamIdPattern<dynamic> other, String otherPath) {
    if (identical(this, other)) return true;
    if (pattern == other.pattern) return true;
    return filter.doesMatchPath(otherPath);
  }

  /// Slower method to filter by path only.
  /// Used for testing
  bool globsPathOnly(String otherPath) {
    return filter.doesMatchPath(otherPath);
  }

  @override
  String toString() => '$runtimeType(pattern: $pattern, filter: $filter)';
}
