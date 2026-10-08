import 'dart:async';

import 'package:claudare_crypto/crypto.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_sync_provider.dart';
import 'package:notes/screens/settings/replication_screen.dart';
import 'package:sync/sync.dart';
import 'package:time_provider/time_provider.dart';

import 'sync_test_transport.dart';

void main() {
  testWidgets('diagnostics switch to a replacement coordinator', (
    tester,
  ) async {
    final old = _Harness();
    old.coordinator.start();
    await tester.pumpWidget(old.screen);
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    await old.coordinator.close();
    final replacement = _Harness();
    final pending = Completer<void>();
    replacement.transport.onStart = () => pending.future;
    replacement.coordinator.start();
    await tester.pumpWidget(replacement.screen);
    expect(find.text('Connecting'), findsOneWidget);
    expect(find.text('Closed'), findsNothing);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
  });

  for (final reason in ['Disabled', 'Not configured']) {
    testWidgets('shows $reason without a coordinator', (tester) async {
      await tester.pumpWidget(
        NoteSyncProvider(
          unavailableReason: reason,
          child: const MaterialApp(home: ReplicationScreen()),
        ),
      );
      expect(find.text(reason), findsOneWidget);
    });
  }

  testWidgets('shows the current snapshot when opened after connection', (
    tester,
  ) async {
    final h = _Harness();
    h.coordinator.start();
    await tester.pump();
    await tester.pumpWidget(h.screen);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('No active peers'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('updates connection and failure information live', (
    tester,
  ) async {
    final h = _Harness();
    final starting = Completer<void>();
    h.transport.onStart = () => starting.future;
    h.coordinator.start();
    await tester.pumpWidget(h.screen);
    expect(find.text('Connecting'), findsOneWidget);
    starting.complete();
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);
    h.transport.discovery.addError(Exception('private error'));
    await tester.pumpAndSettle();
    expect(find.text('Reconnecting'), findsOneWidget);
    expect(
      find.text('Sync transport ended; scheduling reconnect'),
      findsOneWidget,
    );
    expect(find.textContaining('private error'), findsNothing);
    expect(find.text('2026-10-08 12:34:56'), findsOneWidget);
    await h.coordinator.close();
    await tester.pumpAndSettle();
    expect(find.text('Closed'), findsOneWidget);
  });

  testWidgets('updates active peer keys as sessions open and close', (
    tester,
  ) async {
    final h = _Harness();
    final peer = PublicKey.staticValue(2);
    await h.identities.addPeer(PeerActorIdentity(publicKey: peer));
    h.coordinator.start();
    await tester.pumpWidget(h.screen);
    final pair = SyncTestHelper.createPeerPair(
      firstActor: PublicKey.staticValue(1).toString(),
      secondActor: peer.toString(),
    );
    final messages = pair.second.channel.stream.listen((_) {});
    addTearDown(messages.cancel);
    h.transport.discovery.add(pair.first);
    await tester.pumpAndSettle();
    expect(find.text(peer.toString()), findsOneWidget);
    expect(find.text('No active peers'), findsNothing);
    await pair.second.channel.sink.close();
    await tester.pumpAndSettle();
    expect(find.text(peer.toString()), findsNothing);
    expect(find.text('No active peers'), findsOneWidget);
  });
}

class _Harness {
  final transport = TestTransport();
  final identities = MemoryActorIdentityStore();
  late final coordinator = SyncCoordinator(
    eventStore: MemoryEventStore(),
    identityStore: identities,
    createTransport: () => transport,
    logger: const NoopLogger(),
    timeProvider: FakeTimeProviderStatic(DateTime(2026, 10, 8, 12, 34, 56)),
  );

  _Harness() {
    addTearDown(() => coordinator.close());
  }

  Widget get screen => NoteSyncProvider(
    coordinator: coordinator,
    child: const MaterialApp(home: ReplicationScreen()),
  );
}
