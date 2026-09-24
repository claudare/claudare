import 'package:cqrs/cqrs.dart';

import 'account_list.dart';

class AccountListSnapshotter extends MemorySnapshotter<AccountListState>
    implements Snapshotter<AccountListState> {}
