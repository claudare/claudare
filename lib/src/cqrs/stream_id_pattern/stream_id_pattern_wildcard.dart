import 'package:core/src/cqrs/pattern_filter.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class StreamIdPatternWildcard extends StreamIdPattern<String> {
  final String _prefix;

  @override
  final String pattern;

  @override
  final PatternFilter filter;

  StreamIdPatternWildcard(this.pattern)
    : assert(
        pattern.endsWith('*'),
        'Wildcard pattern must end with *. Got: "$pattern"',
      ),
      _prefix = pattern.substring(0, pattern.length - 1),
      filter = PatternFilter.startsWith(
        pattern.substring(0, pattern.length - 1),
      );

  @override
  String toData(String path) {
    // assert(
    //   path.startsWith(_prefix),
    //   'Path $path does not match wildcard pattern: $pattern',
    // );

    // could be passed wrongly...
    if (!path.startsWith(_prefix)) {
      throw ArgumentError.value(
        path,
        'path',
        'Path does not match wildcard pattern',
      );
    }

    return path.substring(_prefix.length);
  }

  @override
  String toPath(String data) => "$_prefix$data";
}
