import 'dart:async';

import 'package:cqrs/cqrs.dart';

class NoteListTestStore extends MemoryEventStore {
  final cancelled = Completer<void>();
  final readStarted = Completer<void>();
  int activeSubscriptions = 0;
  Future<void>? beforeRead;
  Exception? readFailure;

  @override
  Stream<EventChange> get eventChanges => Stream.multi((controller) {
    activeSubscriptions++;
    final subscription = super.eventChanges.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = () async {
      await subscription.cancel();
      activeSubscriptions--;
      if (!cancelled.isCompleted) cancelled.complete();
    };
  });

  @override
  Future<PaginatedResult<StoredEvent>> getLogEvents(
    LogFilter filter,
    int fromPosition,
  ) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await beforeRead;
    if (readFailure != null) throw readFailure!;
    return super.getLogEvents(filter, fromPosition);
  }
}
