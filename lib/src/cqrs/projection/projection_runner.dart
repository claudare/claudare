import 'package:core/src/cqrs/event_store/event_store_projection.dart';
import 'package:core/src/cqrs/projection/projector.dart';
import 'package:core/src/cqrs/stream_id.dart';

class ProjectionRunner<TEvents, TIdData> {
  final EventStoreProjection _eventStore;
  final Projector<TEvents, TIdData> _projector;

  const ProjectionRunner(this._eventStore, this._projector);

  bool shouldProcess(StreamId<dynamic> stream, String onPath) {
    return _projector.eventPack.streamId.matches(stream, onPath);
  }

  bool shouldProcessPath(String onPath) {
    return _projector.eventPack.streamId.filter.doesMatchPath(onPath);
  }

  Future<void> catchupSelfLoad() async {}
}
