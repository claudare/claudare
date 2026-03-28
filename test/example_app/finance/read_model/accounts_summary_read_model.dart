import 'package:core/src/cqrs.dart';

class AccountSummary {
  final String accountId;
  final String name;
  final int balance;
  final int transactionCount;
  final DateTime openedAt;
  final DateTime lastTransactionAt;

  final int lastLocalSequence;

  AccountSummary({
    required this.accountId,
    required this.name,
    required this.balance,
    required this.transactionCount,
    required this.openedAt,
    required this.lastTransactionAt,
    required this.lastLocalSequence,
  });

  AccountSummary copyWith({
    String? name,
    int? balance,
    int? transactionCount,
    DateTime? openedAt,
    DateTime? lastTransactionAt,
    int? lastLocalSequence,
  }) {
    return AccountSummary(
      accountId: accountId,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      transactionCount: transactionCount ?? this.transactionCount,
      openedAt: openedAt ?? this.openedAt,
      lastTransactionAt: lastTransactionAt ?? this.lastTransactionAt,
      lastLocalSequence: lastLocalSequence ?? this.lastLocalSequence,
    );
  }

  @override
  String toString() {
    return 'AccountSummary(accountId: $accountId, name: $name, balance: $balance, transactionCount: $transactionCount, openedAt: $openedAt, lastTransactionAt: $lastTransactionAt, lastLocalSequence: $lastLocalSequence)';
  }
}

// this does include mutations... just dont use them
// following Oskar Dudycz GetAndStore example
// https://event-driven.io/en/projections_and_read_models_in_event_driven_architecture/#talk-is-cheap-show-me-the-code
// this is a memory implementation
class AccountsSummaryReadModel {
  final Map<String, AccountSummary> summaries = {};
  bool _isInitialized = false;

  AccountsSummaryReadModel();

  Future<void> init() async {
    _isInitialized = true;
  }

  Future<void> reset() async {
    summaries.clear();
  }

  Future<ProjectionCheckpoint> checkpoint() async {
    if (!_isInitialized) {
      return ProjectionCheckpoint.zero();
    }

    return ProjectionCheckpoint(
      localSequence: summaries.values.fold(
        0,
        (max, summary) =>
            max > summary.lastLocalSequence ? max : summary.lastLocalSequence,
      ),
      localVersion: 0,
    );
  }

  // mutations (can be moved out, easier to do with sql)
  Future<void> store(String accountId, AccountSummary summary) async {
    // should check everywhere
    if (!_isInitialized) {
      throw Exception("store called before init");
    }

    assert(accountId == summary.accountId);
    summaries[summary.accountId] = summary;
  }

  Future<void> getAndStore(
    String accountId,
    Function(AccountSummary summary) update,
  ) async {
    final summary = await get(accountId);
    if (summary == null) {
      // He does not throw, uses zero value instead
      // I dont want to define zero values as it could be dangerous in long-term
      throw Exception("invalid getAndStore id");
    }

    await store(accountId, await update(summary));
  }

  // Read methods below

  Future<AccountSummary?> get(String accountId) async => summaries[accountId];

  // implement whatever query capability
  Future<List<AccountSummary>> getAllSortedByNameDesc() async =>
      summaries.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  Future<List<AccountSummary>> getAllSortedByBalanceDesc() async =>
      summaries.values.toList()..sort((a, b) => a.balance.compareTo(b.balance));
}
