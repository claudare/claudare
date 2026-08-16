import 'package:cqrs/src/cqrs/pattern_filter.dart';

abstract class StreamRoute<TParams> {
  const StreamRoute();

  String get pattern;
  PatternFilter get filter;

  String buildPath(TParams streamParams);
  TParams parseParams(String streamPath);
  bool matches(String streamPath) => filter.doesMatchPath(streamPath);

  @override
  String toString() => '$runtimeType(pattern: $pattern, filter: $filter)';
}
