import 'package:cqrs/cqrs.dart';

String accountStream(String accountId) => 'account/$accountId';

/// Returns the account ID or throws [FormatException] for an invalid stream path.
String accountIdFromStream(String streamPath) {
  const prefix = 'account/';
  if (!streamPath.startsWith(prefix) || streamPath.length == prefix.length) {
    throw const FormatException('Invalid account stream path');
  }
  return streamPath.substring(prefix.length);
}

LogFilter accountStreamFilter(String accountId) =>
    LogFilter.exact(accountStream(accountId));

final allAccountsFilter = LogFilter.startsWith('account/');
