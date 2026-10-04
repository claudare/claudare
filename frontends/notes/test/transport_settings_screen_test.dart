import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/screens/settings/transport_settings_screen.dart';

void main() {
  testWidgets('missing settings produce empty editable fields', (tester) async {
    await _show(tester, MemoryKv());

    expect(_field(tester, 'Server URL').controller!.text, '');
    expect(_field(tester, 'Group').controller!.text, '');
    expect(_field(tester, 'Server URL').enabled, isTrue);
    expect(_field(tester, 'Group').enabled, isTrue);
    expect(_toggle(tester).value, isFalse);
    expect(_toggle(tester).onChanged, isNull);
  });

  for (final (url, group, configured) in [
    ('', 'notes', false),
    ('invalid', 'notes', false),
    ('https://server.test', 'notes', false),
    ('ws://', 'notes', false),
    ('ws://server.test', '', false),
    ('ws://server.test', '   ', false),
    ('ws://server.test', 'notes', true),
    ('wss://server.test', 'notes', true),
  ]) {
    testWidgets('draft eligibility for URL=$url, group="$group"', (
      tester,
    ) async {
      final kv = MemoryKv();
      await _show(tester, kv);
      await _edit(tester, url: url, group: group);

      expect(_toggle(tester).onChanged != null, configured);
      expect(_button(tester, 'Test connection').onPressed != null, configured);
      expect(await kv.listKeys(''), isEmpty);
    });
  }

  testWidgets('turning off retains fields and saves them together', (
    tester,
  ) async {
    final kv = _ControlledKv();
    await _show(
      tester,
      kv,
      enabled: true,
      url: 'wss://saved.test',
      group: 'notes',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(_field(tester, 'Server URL').controller!.text, 'wss://saved.test');
    expect(_field(tester, 'Group').controller!.text, 'notes');
    expect(await kv.listKeys(''), isEmpty);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(kv.writes, [
      {
        NoteSystem.syncEnabledKey: 'false',
        NoteSystem.serverUrlKey: 'wss://saved.test',
        NoteSystem.groupKey: 'notes',
      },
    ]);
    expect(find.text('Transport settings'), findsOneWidget);
    expect(_button(tester, 'Save').onPressed, isNotNull);
  });

  testWidgets('Save trims URL and preserves entered group', (tester) async {
    final kv = _ControlledKv();
    await _show(tester, kv);
    await _edit(tester, url: ' ws://saved.test ', group: ' notes ');
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(kv.writes.single, {
      NoteSystem.syncEnabledKey: 'true',
      NoteSystem.serverUrlKey: 'ws://saved.test',
      NoteSystem.groupKey: ' notes ',
    });
    await _edit(tester, url: 'ws://changed.test', group: 'changed');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(kv.writes, hasLength(2));
    expect(await kv.getString(NoteSystem.serverUrlKey), 'ws://changed.test');
    expect(await kv.getString(NoteSystem.groupKey), 'changed');
    expect(find.text('Transport settings'), findsOneWidget);
  });

  for (final (url, group, error) in [
    ('invalid', 'notes', 'Enter a ws or wss URL with a host'),
    ('ws://server.test', '', 'Enter a group'),
  ]) {
    testWidgets('enabled transport rejects $error', (tester) async {
      final kv = MemoryKv();
      await _show(
        tester,
        kv,
        enabled: true,
        url: 'ws://server.test',
        group: 'notes',
      );
      await _edit(tester, url: url, group: group);
      expect(_toggle(tester).value, isTrue);
      expect(_toggle(tester).onChanged, isNotNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text(error), findsOneWidget);
      expect(await kv.listKeys(''), isEmpty);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(find.text(error), findsNothing);
    });
  }

  testWidgets('disabled transport can save empty fields', (tester) async {
    final kv = MemoryKv();
    await _show(tester, kv);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await kv.getBool(NoteSystem.syncEnabledKey), isFalse);
    expect(await kv.getString(NoteSystem.serverUrlKey), '');
    expect(await kv.getString(NoteSystem.groupKey), '');
  });

  testWidgets('back navigation discards drafts', (tester) async {
    final kv = MemoryKv();
    await _show(tester, kv);
    await _edit(tester, url: 'ws://draft.test', group: 'draft');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(await kv.listKeys(''), isEmpty);
  });

  testWidgets('pending save blocks editing and repeated saves', (tester) async {
    final pending = Completer<void>();
    final kv = _ControlledKv()..beforeWrite = () => pending.future;
    await _show(tester, kv);
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(_field(tester, 'Server URL').enabled, isFalse);
    expect(_field(tester, 'Group').enabled, isFalse);
    expect(_toggle(tester).onChanged, isNull);
    expect(_button(tester, 'Saving…').onPressed, isNull);
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.text('Transport settings'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(kv.writes, hasLength(1));
    expect(find.text('Transport settings'), findsOneWidget);
    expect(_field(tester, 'Server URL').enabled, isTrue);
    expect(_button(tester, 'Save').onPressed, isNotNull);
  });

  testWidgets('save failure shows generic error and permits retry', (
    tester,
  ) async {
    final kv = _ControlledKv()
      ..beforeWrite = () async => throw Exception('private data');
    await _show(tester, kv);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not save transport settings. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private data'), findsNothing);
    expect(await kv.listKeys(''), isEmpty);
    kv.beforeWrite = null;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(await kv.getBool(NoteSystem.syncEnabledKey), isFalse);
  });

  for (final (server, health) in [
    (
      'ws://server.test:7000/proxy?x=1#fragment',
      'http://server.test:7000/health',
    ),
    ('wss://server.test/proxy', 'https://server.test/health'),
    ('wss://server.test:8443/proxy', 'https://server.test:8443/health'),
  ]) {
    testWidgets('health URL for $server', (tester) async {
      Uri? requested;
      final kv = MemoryKv();
      await _show(
        tester,
        kv,
        url: server,
        group: 'notes',
        check: (uri) async {
          requested = uri;
          return true;
        },
      );
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(requested.toString(), health);
      expect(await kv.listKeys(''), isEmpty);
      expect(_toggle(tester).value, isFalse);
    });
  }

  for (final success in [true, false]) {
    testWidgets('connection result $success changes button color', (
      tester,
    ) async {
      await _show(
        tester,
        MemoryKv(),
        url: 'ws://server.test',
        group: 'notes',
        check: (_) async => success,
      );
      await tester.tap(find.text('Test connection'));
      await tester.pumpAndSettle();

      expect(
        _button(tester, 'Test connection').style!.foregroundColor!.resolve({}),
        success ? Colors.green : Colors.red,
      );
      expect(
        find.text(success ? 'Connection successful' : 'Connection failed'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Group'),
        'changed',
      );
      await tester.pump();
      expect(_button(tester, 'Test connection').style, isNull);
      expect(find.textContaining('Connection '), findsNothing);
    });
  }

  testWidgets('connection exceptions display generic failure', (tester) async {
    await _show(
      tester,
      MemoryKv(),
      url: 'ws://server.test',
      group: 'notes',
      check: (_) async => throw Exception('private data'),
    );
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();

    expect(find.text('Connection failed'), findsOneWidget);
    expect(find.textContaining('private data'), findsNothing);
  });

  for (final field in ['Server URL', 'Group']) {
    testWidgets('editing $field discards pending test result', (tester) async {
      final pending = Completer<bool>();
      await _show(
        tester,
        MemoryKv(),
        url: 'ws://server.test',
        group: 'notes',
        check: (_) => pending.future,
      );
      await tester.tap(find.text('Test connection'));
      await tester.pump();

      expect(_button(tester, 'Testing…').onPressed, isNull);
      expect(_button(tester, 'Save').onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, field), '');
      pending.complete(true);
      await tester.pumpAndSettle();

      expect(find.text('Connection successful'), findsNothing);
      expect(_button(tester, 'Test connection').style, isNull);
      expect(_button(tester, 'Test connection').onPressed, isNull);
      expect(_button(tester, 'Save').onPressed, isNotNull);
    });
  }

  testWidgets('closing screen discards pending test result', (tester) async {
    final pending = Completer<bool>();
    await _show(
      tester,
      MemoryKv(),
      url: 'ws://server.test',
      group: 'notes',
      check: (_) => pending.future,
    );
    await tester.tap(find.text('Test connection'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    pending.complete(true);
    await tester.pumpAndSettle();

    expect(find.text('Transport settings'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(
  WidgetTester tester,
  Kv kv, {
  bool enabled = false,
  String? url,
  String? group,
  Future<bool> Function(Uri)? check,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => TransportSettingsScreen(
                  kv: kv,
                  initialEnabled: enabled,
                  initialServerUrl: url,
                  initialGroup: group,
                  testConnection: check ?? (_) async => true,
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _edit(
  WidgetTester tester, {
  required String url,
  required String group,
}) async {
  await tester.enterText(find.widgetWithText(TextField, 'Server URL'), url);
  await tester.enterText(find.widgetWithText(TextField, 'Group'), group);
  await tester.pump();
}

TextField _field(WidgetTester tester, String label) =>
    tester.widget<TextField>(find.widgetWithText(TextField, label));

SwitchListTile _toggle(WidgetTester tester) =>
    tester.widget<SwitchListTile>(find.byType(SwitchListTile));

ButtonStyleButton _button(WidgetTester tester, String label) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      ),
    );

class _ControlledKv extends MemoryKv {
  final writes = <Map<String, String>>[];
  Future<void> Function()? beforeWrite;

  @override
  Future<void> setAllStrings(Map<String, String> values) async {
    await beforeWrite?.call();
    writes.add(Map.of(values));
    await super.setAllStrings(values);
  }
}
