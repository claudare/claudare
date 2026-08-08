import 'package:core/src/cqrs/pattern_filter.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class StreamIdPatternAll extends StreamIdPattern<String> {
  @override
  final String pattern = '*';

  @override
  final PatternFilter filter = PatternFilter.any();

  // too bad this cant be made const (as comparisons will be made usually)
  StreamIdPatternAll();

  @override
  String toData(String path) {
    return path;
  }

  @override
  String toPath(String data) => data;
}
