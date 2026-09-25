import 'package:cqrs/src/cqrs/pattern_filter.dart';

abstract class StreamRoute {
  const StreamRoute();

  String get pattern;
  PatternFilter get filter;

  String buildPath(String streamParams);
  bool matches(String streamPath) => filter.doesMatchPath(streamPath);

  @override
  String toString() => '$runtimeType(pattern: $pattern, filter: $filter)';
}
