import 'package:cqrs/cqrs.dart';

String accountStream(String accountId) => 'account/$accountId';

LogFilter accountStreamFilter(String accountId) =>
    LogFilter.exact(accountStream(accountId));

final allAccountsFilter = LogFilter.startsWith('account/');
