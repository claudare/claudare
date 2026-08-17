import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

abstract class SqliteProjection<TEvent extends Object, TParams> {
  String get name;
  int get version;
  StreamRoute<TParams> get streamRoute;
  ProjectionFailureHandler get failureHandler;

  Future<void> reset(IsolateSqlite db);

  void apply(
    SyncContext context,
    TParams streamParams,
    TEvent event,
    EventMetadata metadata,
  );

  void onBatchApplied();

  Projection<TEvent, TParams> toProjection(IsolateSqlite db) {
    return _AdaptedSqliteProjection(db, this);
  }
}

final class _AdaptedSqliteProjection<TEvent extends Object, TParams>
    implements Projection<TEvent, TParams> {
  final IsolateSqlite _db;
  final SqliteProjection<TEvent, TParams> _projection;

  const _AdaptedSqliteProjection(this._db, this._projection);

  @override
  String get name => _projection.name;

  @override
  int get version => _projection.version;

  @override
  StreamRoute<TParams> get streamRoute => _projection.streamRoute;

  @override
  ProjectionFailureHandler get failureHandler => _projection.failureHandler;

  @override
  Future<void> reset() => _projection.reset(_db);

  @override
  Future<void> apply(
    TParams streamParams,
    TEvent event,
    EventMetadata metadata,
  ) async {
    await _db.transaction((context) {
      _projection.apply(context, streamParams, event, metadata);
    });
  }

  @override
  void onBatchApplied() => _projection.onBatchApplied();
}
