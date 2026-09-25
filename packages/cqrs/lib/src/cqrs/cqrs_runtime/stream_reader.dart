import 'package:common/common.dart';
import 'package:cqrs/src/cqrs/event/stored_event.dart';

/// Creates a paginated reader for a stream from an inclusive version.
typedef StreamReader =
    PaginatedReader<StoredEvent> Function(String streamPath, {int fromVersion});
