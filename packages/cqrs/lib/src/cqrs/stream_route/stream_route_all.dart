import 'package:cqrs/src/cqrs/pattern_filter.dart';
import 'package:cqrs/src/cqrs/stream_route/stream_route.dart';

class StreamRouteAll extends StreamRoute {
  @override
  final String pattern = '*';

  @override
  final PatternFilter filter = const PatternFilter.any();

  const StreamRouteAll();

  @override
  String buildPath(String streamParams) => streamParams;
}
