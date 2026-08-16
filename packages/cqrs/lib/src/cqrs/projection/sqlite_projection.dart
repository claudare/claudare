import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

abstract class SqliteProjection<Event extends Object, StreamParams> {
  String get name;
  StreamRoute<StreamParams> get streamRoute;
  ProjectionFailureHandler get failureHandler;

  Future<void> reset(IsolateSqlite db);

  void apply(
    SyncContext ctx,
    StreamParams streamParams,
    Event event,
    EventMetadata metadata,
  );

  Projection toProjection(IsolateSqlite db) {
    return _AdaptedSqliteProjection(db, this);
  }
}

class _AdaptedSqliteProjection<Event extends Object, StreamParams>
    implements Projection<Event, StreamParams> {
  final IsolateSqlite _db;
  final SqliteProjection<Event, StreamParams> _projection;

  const _AdaptedSqliteProjection(this._db, this._projection);

  @override
  String get name => _projection.name;

  @override
  StreamRoute<StreamParams> get streamRoute => _projection.streamRoute;

  @override
  ProjectionFailureHandler get failureHandler => _projection.failureHandler;

  @override
  Future<void> reset() async {
    await _projection.reset(_db);
  }

  @override
  Future<void> apply(
    StreamParams streamParams,
    Event event,
    EventMetadata metadata,
  ) async {
    await _db.transaction((tx) {
      _projection.apply(tx, streamParams, event, metadata);
    });
  }
}
