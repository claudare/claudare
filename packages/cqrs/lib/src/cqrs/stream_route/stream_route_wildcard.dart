import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:cqrs/src/cqrs/stream_route/stream_route.dart';

class StreamRouteWildcard extends StreamRoute<String> {
  final String _prefix;

  @override
  final String pattern;

  @override
  final PatternFilter filter;

  // too bad this cant be made const (as comparisons will be made usually)
  StreamRouteWildcard(this.pattern)
    : assert(
        pattern.endsWith('*'),
        'Wildcard pattern must end with *. Got: "$pattern"',
      ),
      _prefix = pattern.substring(0, pattern.length - 1),
      filter = PatternFilter.startsWith(
        pattern.substring(0, pattern.length - 1),
      );

  @override
  String parseParams(String streamPath) {
    if (!streamPath.startsWith(_prefix)) {
      throw ArgumentError.value(
        streamPath,
        'streamPath',
        'Path does not match wildcard pattern',
      );
    }

    return streamPath.substring(_prefix.length);
  }

  @override
  String buildPath(String streamParams) => '$_prefix$streamParams';
}
