import 'package:cqrs/cqrs.dart';

import '../account_event/account.dart';
import '../read_model/total_balance_read_model.dart';
import '../stream_route/account_stream_route.dart';

// counts total balance, runs eventually
class TotalBalanceProjection implements Projection<AccountEvent, String> {
  final TotalBalanceReadModel _repo;

  const TotalBalanceProjection(this._repo);

  @override
  String get name => 'total-balance';

  @override
  get streamRoute => accountStreamRoute;

  @override
  get failureHandler => ThrowingProjectionFailureHandler();

  @override
  Future<void> reset() async {
    await _repo.reset();
  }

  @override
  Future<void> apply(accountId, event, metadata) async {
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
        // no-ops
        break;
    }
  }
}
