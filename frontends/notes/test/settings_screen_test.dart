import 'dart:async';

import 'package:claudare_crypto/crypto.dart';
import 'package:claudare_logging/claudare_logging.dart';
import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/event_store_provider.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/application/note_system_provider.dart';
import 'package:notes/screens/settings/settings_screen.dart';
import 'package:time_provider/time_provider.dart';

import 'package:sync/sync.dart';

void main() {
  testWidgets('enabled transport displays URL at group', (tester) async {
    final kv = _ControlledKv();
    await kv.setAllStrings({
      NoteSystem.syncEnabledKey: 'true',
      NoteSystem.groupKey: '001-notes',
      NoteSystem.serverUrlKey: 'wss://example.test/notes',
    });
    final system = _system(kv);
    final actor = PublicKey.staticValue(42).toString();
    final application = _application(system, actor: actor);
    await tester.pumpWidget(_screen(system, application));
    await tester.pumpAndSettle();

    expect(_value(tester, 'This device actor key'), actor);
    expect(_value(tester, 'Transport'), 'wss://example.test/notes @ 001-notes');
    expect(find.byType(TextField), findsNothing);
    expect(
      {for (final key in await kv.listKeys('')) key: await kv.getString(key)},
      {
        NoteSystem.syncEnabledKey: 'true',
        NoteSystem.groupKey: '001-notes',
        NoteSystem.serverUrlKey: 'wss://example.test/notes',
      },
    );
  });

  testWidgets('missing enabled flag displays disabled transport', (
    tester,
  ) async {
    final system = _system(MemoryKv());
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Transport'), 'Disabled');
  });

  testWidgets('disabled transport retains saved fields in its editor', (
    tester,
  ) async {
    final kv = MemoryKv();
    await kv.setBool(NoteSystem.syncEnabledKey, false);
    await kv.setString(NoteSystem.serverUrlKey, 'wss://saved.test');
    await kv.setString(NoteSystem.groupKey, '');
    final system = _system(kv);
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Transport'), 'Disabled');
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(find.text('Transport settings'), findsOneWidget);
    expect(find.text('wss://saved.test'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Group'))
          .controller!
          .text,
      '',
    );
  });

  testWidgets('pending reads keep all data loading and reset available', (
    tester,
  ) async {
    final pending = Completer<String?>();
    final kv = _ControlledKv()..read = (_) => pending.future;
    final system = _system(kv);
    final application = _application(system);
    await application.command.createNote(application.generateNoteId());
    await tester.pumpWidget(_screen(system, application));
    await tester.pumpAndSettle();

    expect(_value(tester, 'This device actor key'), 'Loading…');
    expect(_value(tester, 'Transport'), 'Loading…');
    expect(_value(tester, 'Peers'), 'Loading…');
    expect(_value(tester, 'Event Count'), 'Loading…');
    expect(_value(tester, 'Command Count'), 'Loading…');
    expect(find.widgetWithText(ListTile, 'Loading…'), findsNWidgets(6));
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Peers')).onTap,
      isNull,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Transport')).onTap,
      isNull,
    );
    await tester.ensureVisible(find.text('Reset database'));
    await tester.tap(find.text('Reset database'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    pending.complete(null);
    await tester.pumpAndSettle();

    expect(_value(tester, 'Transport'), 'Disabled');
    expect(_value(tester, 'This device actor key'), application.actor);
    expect(_value(tester, 'Active Note Count'), '1');
    expect(_value(tester, 'Event Count'), '1');
    expect(_value(tester, 'Command Count'), '1');
  });

  testWidgets('read failures show one error state and leave reset available', (
    tester,
  ) async {
    final kv = _ControlledKv()
      ..read = (_) async => throw Exception('private settings data');
    final system = _system(kv);
    final application = _application(system);
    await application.command.createNote(application.generateNoteId());
    await tester.pumpWidget(_screen(system, application));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Transport'), 'Could not load settings');
    expect(find.textContaining('private settings data'), findsNothing);
    expect(
      find.widgetWithText(ListTile, 'Could not load settings'),
      findsNWidgets(6),
    );
    await tester.ensureVisible(find.text('Reset database'));
    await tester.tap(find.text('Reset database'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('widget rebuilds reload the saved settings', (tester) async {
    final kv = _ControlledKv();
    await kv.setBool(NoteSystem.syncEnabledKey, true);
    await kv.setString(NoteSystem.serverUrlKey, 'wss://saved.test');
    await kv.setString(NoteSystem.groupKey, 'before');
    final system = _system(kv);
    final application = _application(system);
    await tester.pumpWidget(_screen(system, application));
    await tester.pumpAndSettle();
    expect(kv.reads, 3);
    expect(_value(tester, 'Transport'), 'wss://saved.test @ before');

    await kv.setString(NoteSystem.groupKey, 'after');
    await tester.pumpWidget(_screen(system, application));
    await tester.pumpAndSettle();

    expect(kv.reads, 6);
    expect(_value(tester, 'Transport'), 'wss://saved.test @ after');
  });

  testWidgets('a replacement system discards late results from old reads', (
    tester,
  ) async {
    final pending = Completer<String?>();
    final oldKv = _ControlledKv()..read = (_) => pending.future;
    final oldSystem = _system(oldKv);
    final application = _application(oldSystem);
    await tester.pumpWidget(_screen(oldSystem, application));
    await tester.pumpAndSettle();

    final newKv = _ControlledKv();
    await newKv.setAllStrings({
      NoteSystem.syncEnabledKey: 'true',
      NoteSystem.groupKey: 'new group',
      NoteSystem.serverUrlKey: 'wss://new.test',
    });
    final newSystem = _system(newKv);
    await tester.pumpWidget(_screen(newSystem, application));
    await tester.pumpAndSettle();
    expect(_value(tester, 'Transport'), 'wss://new.test @ new group');

    pending.complete(null);
    await tester.pumpAndSettle();

    expect(_value(tester, 'Transport'), 'wss://new.test @ new group');
    expect(find.text('old value'), findsNothing);
    expect(newKv.reads, 3);
  });

  testWidgets('replacement application updates the displayed actor', (
    tester,
  ) async {
    final system = _system(MemoryKv());
    final firstActor = PublicKey.staticValue(1).toString();
    final secondActor = PublicKey.staticValue(2).toString();
    await tester.pumpWidget(
      _screen(system, _application(system, actor: firstActor)),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _screen(system, _application(system, actor: secondActor)),
    );
    await tester.pumpAndSettle();

    expect(_value(tester, 'This device actor key'), secondActor);
    expect(find.text(firstActor), findsNothing);
  });

  testWidgets('long device and server values wrap on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final url = 'wss://example.test/${'long-path/' * 12}';
    final kv = MemoryKv();
    await kv.setBool(NoteSystem.syncEnabledKey, true);
    await kv.setString(NoteSystem.groupKey, 'notes');
    await kv.setString(NoteSystem.serverUrlKey, url);
    final system = _system(kv);
    final actor = PublicKey.staticValue(42).toString();
    await tester.pumpWidget(
      _screen(system, _application(system, actor: actor)),
    );
    await tester.pumpAndSettle();

    expect(_value(tester, 'This device actor key'), actor);
    expect(_value(tester, 'Transport'), '$url @ notes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('back after saving transport settings refreshes the tile', (
    tester,
  ) async {
    final kv = MemoryKv();
    final system = _system(kv);
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Server URL'),
      'ws://saved.test',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Group'), 'notes');
    await tester.pump();
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Transport settings'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Group'), 'unsaved');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Transport'), 'ws://saved.test @ notes');
  });

  testWidgets('Peers appears below the device key with its saved count', (
    tester,
  ) async {
    final system = _system(MemoryKv());
    for (final value in [1, 2]) {
      await system.identities.addPeer(
        PeerActorIdentity(publicKey: PublicKey.staticValue(value)),
      );
    }
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Peers'), '2');
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles[0].title as Text).data, 'This device actor key');
    expect((tiles[1].title as Text).data, 'Peers');
    expect(tiles[1].subtitle, isA<Text>());
  });

  for (final remove in [false, true]) {
    testWidgets('returning from Peers refreshes count after remove=$remove', (
      tester,
    ) async {
      final system = _system(MemoryKv());
      final key = PublicKey.staticValue(42);
      if (remove) {
        await system.identities.addPeer(PeerActorIdentity(publicKey: key));
      }
      await tester.pumpWidget(_screen(system, _application(system)));
      await tester.pumpAndSettle();
      final subtitle = find.descendant(
        of: find.widgetWithText(ListTile, 'Peers'),
        matching: find.text(remove ? '1' : '0'),
      );
      await tester.tap(subtitle);
      await tester.pumpAndSettle();
      expect(find.text('Peers'), findsOneWidget);
      if (remove) {
        await tester.tap(find.text('Remove'));
      } else {
        await tester.enterText(
          find.widgetWithText(TextField, 'Public key'),
          key.toString(),
        );
        await tester.tap(find.text('Add'));
      }
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(_value(tester, 'Peers'), remove ? '0' : '1');
    });
  }

  testWidgets('peer read failure leaves Peers unavailable with generic error', (
    tester,
  ) async {
    final identities = _FailingIdentities();
    final system = _system(MemoryKv(), identities: identities);
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Peers'), 'Could not load settings');
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, 'Peers')).onTap,
      isNull,
    );
    expect(find.textContaining('private data'), findsNothing);
  });

  for (final (eventPosition, commandPosition, events, commands) in [
    (null, null, '0', '0'),
    (0, 0, '1', '1'),
    (4, 1, '5', '2'),
  ]) {
    testWidgets(
      'store log positions $eventPosition/$commandPosition determine counts',
      (tester) async {
        final store = _ControlledEventStore()
          ..readState = () async => EventDatabaseState(
            lastEventLogPosition: eventPosition,
            lastCommandLogPosition: commandPosition,
            logVersion: CommandDependency(),
          );
        final system = _system(MemoryKv(), eventStore: store);
        await tester.pumpWidget(_screen(system, _application(system)));
        await tester.pumpAndSettle();

        expect(_value(tester, 'Event Count'), events);
        expect(_value(tester, 'Command Count'), commands);
        expect(_value(tester, 'Active Note Count'), '0');
      },
    );
  }

  testWidgets('pending store state keeps event and command counts loading', (
    tester,
  ) async {
    final pending = Completer<EventDatabaseState>();
    final store = _ControlledEventStore()..readState = () => pending.future;
    final system = _system(MemoryKv(), eventStore: store);
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Event Count'), 'Loading…');
    expect(_value(tester, 'Command Count'), 'Loading…');
    pending.complete(
      EventDatabaseState(
        lastEventLogPosition: 2,
        lastCommandLogPosition: 1,
        logVersion: CommandDependency(),
      ),
    );
    await tester.pumpAndSettle();
    expect(_value(tester, 'Event Count'), '3');
    expect(_value(tester, 'Command Count'), '2');
  });

  testWidgets('store state failure shows generic count errors', (tester) async {
    final store = _ControlledEventStore()
      ..readState = () async => throw Exception('private store data');
    final system = _system(MemoryKv(), eventStore: store);
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Event Count'), 'Could not load settings');
    expect(_value(tester, 'Command Count'), 'Could not load settings');
    expect(find.textContaining('private store data'), findsNothing);
  });
}

NoteSystem _system(
  Kv kv, {
  ActorIdentityStore? identities,
  EventStore? eventStore,
}) => NoteSystem(
  identities: identities ?? MemoryActorIdentityStore(),
  kv: kv,
  eventStore: eventStore ?? MemoryEventStore(),
);

NotesApp _application(NoteSystem system, {String actor = 'local'}) => NotesApp(
  cqrsRuntime: CqrsRuntime(
    eventStore: system.eventStore,
    actor: actor,
    logger: const NoopLogger(),
    timeProvider: FakeTimeProviderStatic.zero(),
  ),
);

Widget _screen(NoteSystem system, NotesApp application) => NotesAppProvider(
  application: application,
  child: NoteSystemProvider(
    system: system,
    child: EventStoreProvider(
      eventStore: system.eventStore,
      reset: (_) async {},
      child: const MaterialApp(home: SettingsScreen()),
    ),
  ),
);

String _value(WidgetTester tester, String label) {
  final subtitle = tester
      .widget<ListTile>(find.widgetWithText(ListTile, label))
      .subtitle!;
  return subtitle is Text ? subtitle.data! : (subtitle as SelectableText).data!;
}

class _ControlledKv extends MemoryKv {
  Future<String?> Function(String key)? read;
  int reads = 0;

  @override
  Future<String?> getString(String key) {
    reads++;
    return read?.call(key) ?? super.getString(key);
  }
}

class _FailingIdentities extends MemoryActorIdentityStore {
  @override
  Future<List<PeerActorIdentity>> allPeers() async =>
      throw Exception('private data');
}

class _ControlledEventStore extends MemoryEventStore {
  Future<EventDatabaseState> Function()? readState;

  @override
  Future<EventDatabaseState> getState() =>
      readState?.call() ?? super.getState();
}
