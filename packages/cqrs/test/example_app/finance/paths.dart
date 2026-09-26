import 'package:cqrs/cqrs.dart';

String accountStream(String accountId) => 'account/$accountId';

PatternFilter accountStreamFilter(String accountId) =>
    PatternFilter.exact(accountStream(accountId));

final allAccountsFilter = PatternFilter.startsWith('account/');
