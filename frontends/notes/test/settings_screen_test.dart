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
    expect(find.widgetWithText(ListTile, 'Loading…'), findsNWidgets(4));
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
    expect(find.widgetWithText(ListTile, '1'), findsNWidgets(2));
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
      findsNWidgets(4),
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
}

NoteSystem _system(Kv kv) => NoteSystem(
  identities: MemoryActorIdentityStore(),
  kv: kv,
  eventStore: MemoryEventStore(),
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
