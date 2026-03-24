import 'package:core/src/cqrs/event/event_dependency.dart';

/// TODO: this needs to have dependencies?
class StoredCommandWrite {
  final String kind;
  final String detail;
  final DateTime startedAt;
  final DateTime completedAt;
  final EventDependency dependencies;

  const StoredCommandWrite({
    required this.kind,
    required this.detail,
    required this.startedAt,
    required this.completedAt,
    required this.dependencies,
  });
}

class StoredCommandResult {
  final String? nackReason;
  final Exception? exception; // can this be error too... this is any failure

  const StoredCommandResult({
    required this.nackReason,
    required this.exception,
  });
}

/// [StoredCommandRead] includes everything... probably should be flat
/// this is not gonna be used for a while
class StoredCommandRead {
  final String kind;
  final String detail;
  final DateTime startedAt;
  final DateTime completedAt;
  final EventDependency dependencies;

  final String? nackReason;
  final Exception? exception; // can this be error too... this is any failure

  const StoredCommandRead({
    required this.kind,
    required this.detail,
    required this.startedAt,
    required this.completedAt,
    required this.dependencies,

    required this.nackReason,
    required this.exception,
  });

  StoredCommandResult get result =>
      StoredCommandResult(nackReason: nackReason, exception: exception);
}
