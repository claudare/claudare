import 'package:cqrs/cqrs.dart';
import 'package:isolate_sqlite/isolate_sqlite.dart';

abstract class SqliteProjection {
  String get name;
  int get version;
  ProjectionFailureHandler get failureHandler;

  List<ProjectionRoute> routes(IsolateSqlite db);
  Future<void> reset(IsolateSqlite db);
  void onBatchApplied();

  Projection toProjection(IsolateSqlite db) {
    return _AdaptedSqliteProjection(db, this);
  }
}

final class _AdaptedSqliteProjection implements Projection {
  final IsolateSqlite _db;
  final SqliteProjection _projection;

  const _AdaptedSqliteProjection(this._db, this._projection);

  @override
  String get name => _projection.name;

  @override
  int get version => _projection.version;

  @override
  List<ProjectionRoute> get routes => _projection.routes(_db);

  @override
  ProjectionFailureHandler get failureHandler => _projection.failureHandler;

  @override
  Future<void> reset() => _projection.reset(_db);

  @override
  void onBatchApplied() => _projection.onBatchApplied();
}
