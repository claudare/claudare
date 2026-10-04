import 'dart:async';

import 'package:claudare_crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kv/kv.dart';
import 'package:sync/sync.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/screens/setup/actor_setup.dart';
import 'package:notes/screens/setup/sync_setup.dart';

import 'setup_test_helpers.dart';

void main() {
  Future<void> showActor(WidgetTester tester, ActorIdentityStore store) =>
      tester.pumpWidget(
        MaterialApp(
          home: ActorSetup(identities: store, onSaved: (_) {}),
        ),
      );

  Future<void> showSync(WidgetTester tester, Kv store) => tester.pumpWidget(
    MaterialApp(
      home: SyncSetup(kv: store, onSaved: (_, _) {}),
    ),
  );

  testWidgets('actor key is read-only and starts as a random candidate', (
    tester,
  ) async {
    final store = MemoryActorIdentityStore();
    await showActor(tester, store);
    final key = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(PublicKey.fromString(key).bytes, hasLength(32));
    expect(await store.getLocal(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '0',
    );
  });

  testWidgets('random regeneration replaces the unsaved candidate', (
    tester,
  ) async {
    final store = MemoryActorIdentityStore();
    await showActor(tester, store);
    final before = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data;
    await tester.tap(find.text('Generate random'));
    await tester.pump();
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      isNot(before),
    );
    expect(await store.getLocal(), isNull);
  });

  for (final value in [0, 17, -1]) {
    testWidgets('static value $value is persisted only on Continue', (
      tester,
    ) async {
      final store = MemoryActorIdentityStore();
      await showActor(tester, store);
      await tester.enterText(find.byType(TextField), '$value');
      await tester.tap(find.text('Populate from static value'));
      await tester.pump();
      expect(
        find.text(PublicKey.staticValue(value).toString()),
        findsOneWidget,
      );
      expect(await store.getLocal(), isNull);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect((await store.getLocal())!.publicKey, PublicKey.staticValue(value));
    });
  }

  testWidgets('invalid static input leaves the candidate unchanged', (
    tester,
  ) async {
    await showActor(tester, MemoryActorIdentityStore());
    final before = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data;
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Populate from static value'));
    await tester.pump();
    expect(find.text('Enter a valid integer'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).data,
      before,
    );
  });

  testWidgets('actor save failure stays on setup and permits retry', (
    tester,
  ) async {
    final store = TestIdentities()..saveError = Exception('save failed');
    var advanced = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ActorSetup(identities: store, onSaved: (_) => advanced = true),
      ),
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(advanced, isFalse);
    expect(
      find.text('Could not save actor identity. Try again.'),
      findsOneWidget,
    );
    store.saveError = null;
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(advanced, isTrue);
  });

  testWidgets('actor submission is disabled until persistence completes', (
    tester,
  ) async {
    final pending = Completer<void>();
    final store = TestIdentities()..saveDelay = pending.future;
    await showActor(tester, store);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(await store.getLocal(), isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(await store.getLocal(), isNotNull);
  });

  testWidgets('server URL defaults to localhost', (tester) async {
    final store = MemoryKv();
    await showSync(tester, store);
    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Replication server URL'),
          )
          .controller!
          .text,
      'ws://localhost:7000',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      await store.getString(NoteSystem.serverUrlKey),
      'ws://localhost:7000',
    );
  });

  testWidgets('group defaults to the string zero', (tester) async {
    final store = MemoryKv();
    await showSync(tester, store);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Group'))
          .controller!
          .text,
      '0',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(await store.getString(NoteSystem.groupKey), '0');
  });

  for (final group in ['notes-team', '001', '']) {
    testWidgets('saves group "$group" as a string', (tester) async {
      final store = MemoryKv();
      String? savedGroup;
      await tester.pumpWidget(
        MaterialApp(
          home: SyncSetup(kv: store, onSaved: (_, value) => savedGroup = value),
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Group'), group);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(await store.getString(NoteSystem.groupKey), group);
      expect(savedGroup, group);
    });
  }

  for (final value in ['', 'http://localhost:7000', 'ws:', 'wss:///']) {
    testWidgets('server URL rejects "$value"', (tester) async {
      final store = MemoryKv();
      await showSync(tester, store);
      await tester.enterText(
        find.widgetWithText(TextField, 'Replication server URL'),
        value,
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a ws or wss URL with a host'), findsOneWidget);
      expect(await store.listKeys(''), isEmpty);
    });
  }

  for (final scheme in ['ws', 'wss']) {
    testWidgets('server URL accepts and trims $scheme', (tester) async {
      final store = MemoryKv();
      await showSync(tester, store);
      await tester.enterText(
        find.widgetWithText(TextField, 'Replication server URL'),
        '  $scheme://example.test:7000/path  ',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        await store.getString(NoteSystem.serverUrlKey),
        '$scheme://example.test:7000/path',
      );
    });
  }

  testWidgets('server save failure permits retry without advancing', (
    tester,
  ) async {
    final store = TestKv()..saveError = Exception('save failed');
    var advanced = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SyncSetup(kv: store, onSaved: (_, _) => advanced = true),
      ),
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(advanced, isFalse);
    expect(
      find.text('Could not save sync settings. Try again.'),
      findsOneWidget,
    );
    expect(await store.listKeys(''), isEmpty);
    store.saveError = null;
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(advanced, isTrue);
  });

  testWidgets('server submission waits for persistence', (tester) async {
    final pending = Completer<void>();
    final store = TestKv()..saveDelay = pending.future;
    var advanced = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SyncSetup(kv: store, onSaved: (_, _) => advanced = true),
      ),
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(advanced, isFalse);
    expect(await store.listKeys(''), isEmpty);
    expect(
      tester.widget<TextField>(find.widgetWithText(TextField, 'Group')).enabled,
      isFalse,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(advanced, isTrue);
  });
}
