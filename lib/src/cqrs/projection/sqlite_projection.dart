import 'package:core/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

abstract class SqliteProjection<Event, StreamIdData> {
  String get name;
  StreamIdPattern<StreamIdData> get streamIdPattern;
  EventCodec<Event> get eventCodec;

  void reset(Transaction tx);

  ProjectionCheckpoint checkpoint(Transaction tx);

  void apply(
    Transaction tx,
    StreamIdData idData,
    Event event,
    EventMetadata metadata,
  );

  Projection toProjection(IsolateSqlite db) {
    return _AdaptedSqliteProjection(db, this);
  }
}

class _AdaptedSqliteProjection<Event, StreamIdData>
    implements Projection<Event, StreamIdData> {
  final IsolateSqlite _db;
  final SqliteProjection<Event, StreamIdData> _projection;

  const _AdaptedSqliteProjection(this._db, this._projection);

  @override
  String get name => _projection.name;

  @override
  StreamIdPattern<StreamIdData> get streamIdPattern =>
      _projection.streamIdPattern;

  @override
  EventCodec<Event> get eventCodec => _projection.eventCodec;

  @override
  Future<void> reset() async {
    await _db.transaction((tx) {
      _projection.reset(tx);
    });
  }

  @override
  Future<ProjectionCheckpoint> checkpoint() async {
    return await _db.transaction((tx) {
      return _projection.checkpoint(tx);
    });
  }

  @override
  Future<void> apply(
    StreamIdData idData,
    Event event,
    EventMetadata metadata,
  ) async {
    await _db.transaction((tx) {
      _projection.apply(tx, idData, event, metadata);
    });
  }
}
