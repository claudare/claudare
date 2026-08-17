import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../read_model/total_balance_read_model.dart';
import '../stream_route/account_stream_route.dart';

class TotalBalanceProjection implements Projection<AccountEvent, String> {
  final TotalBalanceReadModel _repo;

  const TotalBalanceProjection(this._repo);

  @override
  String get name => 'total-balance';

  @override
  int get version => 1;

  @override
  StreamRoute<String> get streamRoute => accountStreamRoute;

  @override
  ProjectionFailureHandler get failureHandler =>
      ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() => _repo.reset();

  @override
  void onBatchApplied() {}

  @override
  Future<void> apply(
    String accountId,
    AccountEvent event,
    EventMetadata metadata,
  ) async {
    switch (event) {
      case AccountAtmDeposited(:final amount):
        final currentValue = await _repo.get();
        return _repo.store(currentValue + amount);
      case AccountAtmWithdrawn(:final amount):
        final currentValue = await _repo.get();
        return _repo.store(currentValue - amount);
      case AccountOpened():
      case AccountInnerTransfer():
      case AccountRenamed():
        break;
    }
  }
}
