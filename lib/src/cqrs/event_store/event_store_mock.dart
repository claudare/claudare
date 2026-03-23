import 'event_store.dart';

class EventStoreMock implements EventStore {
  @override
  Future<GetStreamEventsResult> getStreamEventsCursor(
    String streamId,
    int count,
    int? versionCursor,
  ) {
    // TODO: implement getStreamEventsCursor
    throw UnimplementedError();
  }

  @override
  Future<GetStreamMinimalResult> getStreamMinimal(String streamId) {
    // TODO: implement getStreamMinimal
    throw UnimplementedError();
  }

  @override
  Future<void> saveLocalAppends(AppendLocalEvents change) {
    // TODO: implement saveLocalAppends
    throw UnimplementedError();
  }
}
