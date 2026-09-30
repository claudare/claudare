import 'dart:async';

import 'package:claudare_crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/screens/setup/actor_setup.dart';
import 'package:notes/screens/setup/sync_setup.dart';

import 'setup_test_helpers.dart';

void main() {
  Future<void> showActor(WidgetTester tester, TestIdentities store) =>
      tester.pumpWidget(
        MaterialApp(
          home: ActorSetup(identities: store, onSaved: (_) {}),
        ),
      );

  Future<void> showSync(WidgetTester tester, TestKv store) => tester.pumpWidget(
    MaterialApp(
      home: SyncSetup(kv: store, onSaved: (_) {}),
    ),
  );

  testWidgets('actor key is read-only and starts as a random candidate', (
    tester,
  ) async {
    final store = TestIdentities();
    await showActor(tester, store);
    final key = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(PublicKey.fromString(key).bytes, hasLength(32));
    expect(store.local, isNull);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '0',
    );
  });

  testWidgets('random regeneration replaces the unsaved candidate', (
    tester,
  ) async {
    final store = TestIdentities();
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
    expect(store.local, isNull);
  });

  for (final value in [0, 17, -1]) {
    testWidgets('static value $value is persisted only on Continue', (
      tester,
    ) async {
      final store = TestIdentities();
      await showActor(tester, store);
      await tester.enterText(find.byType(TextField), '$value');
      await tester.tap(find.text('Populate from static value'));
      await tester.pump();
      expect(
        find.text(PublicKey.staticValue(value).toString()),
        findsOneWidget,
      );
      expect(store.local, isNull);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(store.local!.publicKey, PublicKey.staticValue(value));
    });
  }

  testWidgets('invalid static input leaves the candidate unchanged', (
    tester,
  ) async {
    await showActor(tester, TestIdentities());
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
    expect(store.local, isNull);
    pending.complete();
    await tester.pumpAndSettle();
    expect(store.local, isNotNull);
  });

  testWidgets('server URL defaults to localhost', (tester) async {
    final store = TestKv();
    await showSync(tester, store);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'ws://localhost:7000',
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(store.values, {NoteSystem.serverUrlKey: 'ws://localhost:7000'});
  });

  for (final value in ['', 'http://localhost:7000', 'ws:', 'wss:///']) {
    testWidgets('server URL rejects "$value"', (tester) async {
      final store = TestKv();
      await showSync(tester, store);
      await tester.enterText(find.byType(TextField), value);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a ws or wss URL with a host'), findsOneWidget);
      expect(store.values, isEmpty);
    });
  }

  for (final scheme in ['ws', 'wss']) {
    testWidgets('server URL accepts and trims $scheme', (tester) async {
      final store = TestKv();
      await showSync(tester, store);
      await tester.enterText(
        find.byType(TextField),
        '  $scheme://example.test:7000/path  ',
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        store.values[NoteSystem.serverUrlKey],
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
        home: SyncSetup(kv: store, onSaved: (_) => advanced = true),
      ),
    );
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(advanced, isFalse);
    expect(find.text('Could not save server URL. Try again.'), findsOneWidget);
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
        home: SyncSetup(kv: store, onSaved: (_) => advanced = true),
      ),
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(advanced, isFalse);
    pending.complete();
    await tester.pumpAndSettle();
    expect(advanced, isTrue);
  });
}
