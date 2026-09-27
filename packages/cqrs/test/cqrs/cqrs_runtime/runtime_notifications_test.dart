import 'dart:async';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';
import 'package:cqrs/cqrs_test_utils.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runtime subscriptions forward notifications without reading events',
    () async {
      final store = _CountingEventStore();
      final runtime = CqrsTestRuntime(eventStore: store);
      final notifications = StreamIterator(
        runtime.subscribe(const PatternFilter.exact('account/one')),
      );
      addTearDown(notifications.cancel);
      final next = notifications.moveNext();

      runtime.notificationBus.notify('other/one');
      runtime.notificationBus.notify('account/one');

      expect(await next, isTrue);
      expect(notifications.current, 'account/one');
      expect(store.logReads, 0);
    },
  );
}

class _CountingEventStore extends MemoryEventStore {
  var logReads = 0;

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(int fromPosition) {
    logReads++;
    return super.getLogEvents(fromPosition);
  }
}
