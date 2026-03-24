import 'package:core/src/cqrs/pattern_filter.dart';

// TODO: rename to StreamPath or something like this...
// StreamLocation, ... ?
class StreamId<TData> {
  final String pattern;
  final PatternFilter filter;
  final TData Function(String path) parse;
  final String Function(TData) toStr;

  StreamId({
    required this.pattern,
    PatternFilter? filter,
    required this.parse,
    required this.toStr,
  }) : filter = filter ?? PatternFilter.fromString(pattern);

  // returns true if the this aggregate path "globs" (or matches) the other one
  // for example:
  // if this is "*" and other is "doc/*", it matches
  // if this is "account/*" and other path is "account/123", it matches
  // if this is "doc/*" and other is "account/*", it does not match
  matches(StreamId<dynamic> other, String otherPath) {
    // if the same object is reused, its a quick yes
    if (identical(this, other)) {
      return true;
    }
    // matching patterns are also a quick
    if (pattern == other.pattern) {
      return true;
    }
    // otherwise check in depth
    return filter.doesMatchPath(otherPath);
  }
}
