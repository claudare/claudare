import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/projection/projection.dart';
import 'package:core/src/cqrs/stream_id_pattern/stream_id_pattern.dart';

class ProjectionRuntime<TEvents, TIdData> {
  final EventStoreProjection _eventStore;
  final Projection<TEvents, TIdData> _projector;

  const ProjectionRuntime(this._eventStore, this._projector);

  bool shouldProcess(StreamIdPattern<dynamic> streamIdPattern, String onPath) {
    return _projector.streamIdPattern.globs(streamIdPattern, onPath);
  }

  // TODO:rename to acceptsPath
  bool shouldProcessPath(String onPath) {
    return _projector.streamIdPattern.filter.doesMatchPath(onPath);
  }

  Future<void> catchupSelfLoad() async {}
}
