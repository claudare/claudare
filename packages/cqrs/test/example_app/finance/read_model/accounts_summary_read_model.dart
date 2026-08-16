class AccountSummary {
  final String accountId;
  final String name;
  final int balance;
  final int transactionCount;
  final DateTime openedAt;
  final DateTime lastTransactionAt;

  AccountSummary({
    required this.accountId,
    required this.name,
    required this.balance,
    required this.transactionCount,
    required this.openedAt,
    required this.lastTransactionAt,
  });

  AccountSummary copyWith({
    String? name,
    int? balance,
    int? transactionCount,
    DateTime? openedAt,
    DateTime? lastTransactionAt,
  }) {
    return AccountSummary(
      accountId: accountId,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      transactionCount: transactionCount ?? this.transactionCount,
      openedAt: openedAt ?? this.openedAt,
      lastTransactionAt: lastTransactionAt ?? this.lastTransactionAt,
    );
  }

  @override
  String toString() {
    return 'AccountSummary(accountId: $accountId, name: $name, balance: $balance, transactionCount: $transactionCount, openedAt: $openedAt, lastTransactionAt: $lastTransactionAt)';
  }
}

// this does include mutations... just dont use them
// following Oskar Dudycz GetAndStore example
// https://event-driven.io/en/projections_and_read_models_in_event_driven_architecture/#talk-is-cheap-show-me-the-code
// this is a memory implementation
class AccountsSummaryReadModel {
  final Map<String, AccountSummary> summaries = {};
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  AccountsSummaryReadModel();

  // Future<void> init() async {
  //   _isInitialized = true;
  // }

  Future<void> reset() async {
    _isInitialized = true;
    summaries.clear();
  }

  // mutations (can be moved out, easier to do with sql)
  Future<void> store(String accountId, AccountSummary summary) async {
    // should check everywhere
    if (!_isInitialized) {
      throw StateError('read model not initialized');
    }

    assert(accountId == summary.accountId);
    summaries[summary.accountId] = summary;
  }

  Future<void> getAndStore(
    String accountId,
    AccountSummary Function(AccountSummary summary) update,
  ) async {
    if (!_isInitialized) {
      throw StateError('read model not initialized');
    }

    final summary = await get(accountId);
    if (summary == null) {
      // He does not throw, uses zero value instead
      // I dont want to define zero values as it could be dangerous in long-term
      throw Exception('invalid getAndStore id');
    }

    await store(accountId, update(summary));
  }

  // Read methods below

  Future<AccountSummary?> get(String accountId) async {
    if (!_isInitialized) {
      throw StateError('read model not initialized');
    }

    return summaries[accountId];
  }

  // implement whatever query capability
  Future<List<AccountSummary>> getAllSortedByNameDesc() async {
    if (!_isInitialized) {
      throw StateError('read model not initialized');
    }

    return summaries.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<List<AccountSummary>> getAllSortedByBalanceDesc() async {
    if (!_isInitialized) {
      throw StateError('read model not initialized');
    }

    return summaries.values.toList()
      ..sort((a, b) => a.balance.compareTo(b.balance));
  }
}
