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

import 'setup/setup_test_helpers.dart';

void main() {
  testWidgets('device and sync details are selectable and read-only', (
    tester,
  ) async {
    final kv = _ControlledKv()
      ..values[NoteSystem.groupKey] = '001-notes'
      ..values[NoteSystem.serverUrlKey] = 'wss://example.test/notes';
    final system = _system(kv);
    final actor = PublicKey.staticValue(42).toString();
    final application = _application(system, actor: actor);
    await tester.pumpWidget(_screen(system, application));
    await tester.pumpAndSettle();

    expect(_value(tester, 'This device actor key'), actor);
    expect(_value(tester, 'Group'), '001-notes');
    expect(_value(tester, 'Server URL'), 'wss://example.test/notes');
    expect(find.byType(TextField), findsNothing);
    expect(kv.values, {
      NoteSystem.groupKey: '001-notes',
      NoteSystem.serverUrlKey: 'wss://example.test/notes',
    });
  });

  testWidgets('missing saved settings are shown as not configured', (
    tester,
  ) async {
    final system = _system(TestKv());
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Group'), 'Not configured');
    expect(_value(tester, 'Server URL'), 'Not configured');
  });

  testWidgets('an empty saved group is preserved', (tester) async {
    final kv = TestKv()..values[NoteSystem.groupKey] = '';
    final system = _system(kv);
    await tester.pumpWidget(_screen(system, _application(system)));
    await tester.pumpAndSettle();

    expect(_value(tester, 'Group'), '');
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
    expect(_value(tester, 'Group'), 'Loading…');
    expect(_value(tester, 'Server URL'), 'Loading…');
    expect(find.widgetWithText(ListTile, 'Loading…'), findsNWidgets(5));
    await tester.ensureVisible(find.text('Reset database'));
    await tester.tap(find.text('Reset database'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    pending.complete('saved value');
    await tester.pumpAndSettle();

    expect(_value(tester, 'Group'), 'saved value');
    expect(_value(tester, 'Server URL'), 'saved value');
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

    expect(_value(tester, 'Group'), 'Could not load settings');
    expect(_value(tester, 'Server URL'), 'Could not load settings');
    expect(find.textContaining('private settings data'), findsNothing);
    expect(
      find.widgetWithText(ListTile, 'Could not load settings'),
      findsNWidgets(5),
    );
    await tester.ensureVisible(find.text('Reset database'));
    await tester.tap(find.text('Reset database'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('widget rebuilds reload the saved settings', (tester) async {
    final kv = _ControlledKv()..values[NoteSystem.groupKey] = 'before';
    final system = _system(kv);
    final application = _application(system);
    await tester.pumpWidget(_screen(system, application));
    await tester.pumpAndSettle();
    expect(kv.reads, 2);
    expect(_value(tester, 'Group'), 'before');

    kv.values[NoteSystem.groupKey] = 'after';
    await tester.pumpWidget(_screen(system, application));
    await tester.pumpAndSettle();

    expect(kv.reads, 4);
    expect(_value(tester, 'Group'), 'after');
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

    final newKv = _ControlledKv()
      ..values[NoteSystem.groupKey] = 'new group'
      ..values[NoteSystem.serverUrlKey] = 'wss://new.test';
    final newSystem = _system(newKv);
    await tester.pumpWidget(_screen(newSystem, application));
    await tester.pumpAndSettle();
    expect(_value(tester, 'Group'), 'new group');
    expect(_value(tester, 'Server URL'), 'wss://new.test');

    pending.complete('old value');
    await tester.pumpAndSettle();

    expect(_value(tester, 'Group'), 'new group');
    expect(_value(tester, 'Server URL'), 'wss://new.test');
    expect(find.text('old value'), findsNothing);
    expect(newKv.reads, 2);
  });

  testWidgets('replacement application updates the displayed actor', (
    tester,
  ) async {
    final system = _system(TestKv());
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
    final kv = TestKv()..values[NoteSystem.serverUrlKey] = url;
    final system = _system(kv);
    final actor = PublicKey.staticValue(42).toString();
    await tester.pumpWidget(
      _screen(system, _application(system, actor: actor)),
    );
    await tester.pumpAndSettle();

    expect(_value(tester, 'This device actor key'), actor);
    expect(_value(tester, 'Server URL'), url);
    expect(tester.takeException(), isNull);
  });
}

NoteSystem _system(Kv kv) => NoteSystem(
  identities: TestIdentities(),
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

String _value(WidgetTester tester, String label) => tester
    .widget<SelectableText>(
      find.descendant(
        of: find.widgetWithText(ListTile, label),
        matching: find.byType(SelectableText),
      ),
    )
    .data!;

class _ControlledKv extends TestKv {
  Future<String?> Function(String key)? read;
  int reads = 0;

  @override
  Future<String?> get(String key) {
    reads++;
    return read?.call(key) ?? super.get(key);
  }
}
