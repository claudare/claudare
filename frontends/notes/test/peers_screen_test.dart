import 'dart:async';

import 'package:claudare_crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes/screens/settings/peers_screen.dart';
import 'package:sync/sync.dart';

void main() {
  testWidgets('empty peer list has empty key input and static zero', (
    tester,
  ) async {
    await _show(tester, MemoryActorIdentityStore());

    expect(find.text('No peers'), findsOneWidget);
    expect(_field(tester, 'Public key').controller!.text, '');
    expect(_field(tester, 'Static integer value').controller!.text, '0');
    expect(find.text('Save'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('stored peers display read-only keys in store order', (
    tester,
  ) async {
    final identities = MemoryActorIdentityStore();
    for (final value in [256, 2, 1]) {
      await identities.addPeer(
        PeerActorIdentity(publicKey: PublicKey.staticValue(value)),
      );
    }
    await _show(tester, identities);

    final keys = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data)
        .toList();
    expect(keys, [
      for (final value in [1, 2, 256]) PublicKey.staticValue(value).toString(),
    ]);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Remove'), findsNWidgets(3));
  });

  testWidgets('adding a trimmed key persists immediately and clears input', (
    tester,
  ) async {
    final identities = MemoryActorIdentityStore();
    final key = PublicKey.staticValue(42);
    await _show(tester, identities);
    await tester.enterText(
      find.widgetWithText(TextField, 'Public key'),
      ' ${key.toString()} ',
    );
    await _tap(tester, 'Add');

    expect((await identities.allPeers()).map((peer) => peer.publicKey), [key]);
    expect(find.text(key.toString()), findsOneWidget);
    expect(_field(tester, 'Public key').controller!.text, '');
    expect(find.text('Peers'), findsOneWidget);
    expect(find.text('No peers'), findsNothing);
  });

  for (final value in [0, 42, -1]) {
    testWidgets('static value $value populates key without saving', (
      tester,
    ) async {
      final identities = MemoryActorIdentityStore();
      await _show(tester, identities);
      await tester.enterText(
        find.widgetWithText(TextField, 'Static integer value'),
        '$value',
      );
      await _tap(tester, 'Populate from static value');

      expect(
        _field(tester, 'Public key').controller!.text,
        PublicKey.staticValue(value).toString(),
      );
      expect(await identities.allPeers(), isEmpty);
      await _tap(tester, 'Add');
      expect(
        (await identities.allPeers()).single.publicKey,
        PublicKey.staticValue(value),
      );
    });
  }

  testWidgets('invalid static value preserves key and permits correction', (
    tester,
  ) async {
    final identities = MemoryActorIdentityStore();
    final key = PublicKey.staticValue(42).toString();
    await _show(tester, identities);
    await tester.enterText(find.widgetWithText(TextField, 'Public key'), key);
    await tester.enterText(
      find.widgetWithText(TextField, 'Static integer value'),
      'invalid',
    );
    await _tap(tester, 'Populate from static value');

    expect(find.text('Enter a valid integer'), findsOneWidget);
    expect(_field(tester, 'Public key').controller!.text, key);
    expect(await identities.allPeers(), isEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, 'Static integer value'),
      '7',
    );
    await _tap(tester, 'Populate from static value');
    expect(find.text('Enter a valid integer'), findsNothing);
    expect(
      _field(tester, 'Public key').controller!.text,
      PublicKey.staticValue(7).toString(),
    );
  });

  for (final value in ['', '0-invalid', '1', '1' * 33]) {
    testWidgets('invalid public key "$value" is rejected', (tester) async {
      final identities = MemoryActorIdentityStore();
      await _show(tester, identities);
      await tester.enterText(
        find.widgetWithText(TextField, 'Public key'),
        value,
      );
      await _tap(tester, 'Add');

      expect(find.text('Enter a valid public key'), findsOneWidget);
      expect(await identities.allPeers(), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('duplicate peer is rejected without adding another identity', (
    tester,
  ) async {
    final identities = MemoryActorIdentityStore();
    final key = PublicKey.staticValue(42);
    await identities.addPeer(PeerActorIdentity(publicKey: key));
    await _show(tester, identities);
    await tester.enterText(
      find.widgetWithText(TextField, 'Public key'),
      key.toString(),
    );
    await _tap(tester, 'Add');

    expect(find.text('Peer already exists'), findsOneWidget);
    expect(await identities.allPeers(), hasLength(1));
  });

  testWidgets('Remove immediately deletes only the selected peer', (
    tester,
  ) async {
    final identities = MemoryActorIdentityStore();
    final key = PublicKey.staticValue(42);
    final other = PublicKey.staticValue(43);
    await identities.setLocal(LocalActorIdentity(publicKey: key));
    for (final peer in [key, other]) {
      await identities.addPeer(PeerActorIdentity(publicKey: peer));
    }
    await _show(tester, identities);
    await tester.tap(_remove(key));
    await tester.pumpAndSettle();

    expect((await identities.allPeers()).map((peer) => peer.publicKey), [
      other,
    ]);
    expect((await identities.getLocal())!.publicKey, key);
    expect(find.text(key.toString()), findsNothing);
    expect(find.text(other.toString()), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Peers'), findsOneWidget);
  });

  testWidgets('adding a peer preserves the local identity', (tester) async {
    final identities = MemoryActorIdentityStore();
    final local = PublicKey.staticValue(42);
    await identities.setLocal(LocalActorIdentity(publicKey: local));
    await _show(tester, identities);
    await tester.enterText(
      find.widgetWithText(TextField, 'Public key'),
      PublicKey.staticValue(43).toString(),
    );
    await _tap(tester, 'Add');

    expect((await identities.getLocal())!.publicKey, local);
  });

  testWidgets('removing the last peer displays empty state', (tester) async {
    final identities = MemoryActorIdentityStore();
    final key = PublicKey.staticValue(42);
    await identities.addPeer(PeerActorIdentity(publicKey: key));
    await _show(tester, identities);
    await tester.tap(_remove(key));
    await tester.pumpAndSettle();

    expect(find.text('No peers'), findsOneWidget);
    expect(await identities.allPeers(), isEmpty);
  });

  testWidgets('pending reads disable mutation controls', (tester) async {
    final pending = Completer<void>();
    final identities = _ControlledIdentities()
      ..beforeRead = () => pending.future;
    await _show(tester, identities);

    expect(find.text('Loading…'), findsOneWidget);
    expect(_field(tester, 'Public key').enabled, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('No peers'), findsOneWidget);
    expect(_field(tester, 'Public key').enabled, isTrue);
  });

  testWidgets('load failure shows generic error and permits retry', (
    tester,
  ) async {
    final identities = _ControlledIdentities()
      ..beforeRead = () async => throw Exception('private data');
    await _show(tester, identities);

    expect(find.text('Could not load peers. Try again.'), findsOneWidget);
    expect(find.textContaining('private data'), findsNothing);
    expect(_field(tester, 'Public key').enabled, isFalse);
    identities.beforeRead = null;
    await _tap(tester, 'Retry');
    expect(find.text('No peers'), findsOneWidget);
    expect(_field(tester, 'Public key').enabled, isTrue);
  });

  for (final remove in [false, true]) {
    testWidgets('pending mutation blocks repeated actions for remove=$remove', (
      tester,
    ) async {
      final identities = _ControlledIdentities();
      final key = PublicKey.staticValue(42);
      if (remove) await identities.addPeer(PeerActorIdentity(publicKey: key));
      final pending = Completer<void>();
      identities.beforeWrite = () => pending.future;
      await _show(tester, identities);
      if (remove) {
        await tester.tap(_remove(key));
      } else {
        await tester.enterText(
          find.widgetWithText(TextField, 'Public key'),
          key.toString(),
        );
        await tester.tap(find.text('Add'));
      }
      await tester.pump();

      expect(_field(tester, 'Public key').enabled, isFalse);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
            .onPressed,
        isNull,
      );
      if (remove) {
        expect(tester.widget<TextButton>(_remove(key)).onPressed, isNull);
      }
      pending.complete();
      await tester.pumpAndSettle();
      expect(await identities.allPeers(), hasLength(remove ? 0 : 1));
      expect(_field(tester, 'Public key').enabled, isTrue);
    });

    testWidgets(
      'failed mutation preserves data and permits retry for remove=$remove',
      (tester) async {
        final identities = _ControlledIdentities();
        final key = PublicKey.staticValue(42);
        if (remove) await identities.addPeer(PeerActorIdentity(publicKey: key));
        identities.beforeWrite = () async => throw Exception('private data');
        await _show(tester, identities);
        if (remove) {
          await tester.tap(_remove(key));
          await tester.pumpAndSettle();
        } else {
          await tester.enterText(
            find.widgetWithText(TextField, 'Public key'),
            key.toString(),
          );
          await _tap(tester, 'Add');
        }

        expect(
          find.text(
            remove
                ? 'Could not remove peer. Try again.'
                : 'Could not add peer. Try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('private data'), findsNothing);
        expect(await identities.allPeers(), hasLength(remove ? 1 : 0));
        if (!remove) {
          expect(_field(tester, 'Public key').controller!.text, key.toString());
        }
        identities.beforeWrite = null;
        if (remove) {
          await tester.tap(_remove(key));
          await tester.pumpAndSettle();
        } else {
          await _tap(tester, 'Add');
        }
        expect(await identities.allPeers(), hasLength(remove ? 0 : 1));
      },
    );
  }
}

Future<void> _show(WidgetTester tester, ActorIdentityStore identities) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => PeersScreen(identities: identities),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, 'Open');
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester, String label) =>
    tester.widget<TextField>(find.widgetWithText(TextField, label));

Finder _remove(PublicKey key) => find.descendant(
  of: find.byKey(ValueKey(key)),
  matching: find.widgetWithText(TextButton, 'Remove'),
);

class _ControlledIdentities extends MemoryActorIdentityStore {
  Future<void> Function()? beforeRead;
  Future<void> Function()? beforeWrite;

  @override
  Future<List<PeerActorIdentity>> allPeers() async {
    await beforeRead?.call();
    return super.allPeers();
  }

  @override
  Future<void> addPeer(PeerActorIdentity identity) async {
    await beforeWrite?.call();
    await super.addPeer(identity);
  }

  @override
  Future<void> deletePeer(PublicKey key) async {
    await beforeWrite?.call();
    await super.deletePeer(key);
  }
}
