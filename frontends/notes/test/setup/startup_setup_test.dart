import 'package:claudare_logging/claudare_logging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kv/kv.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/main.dart';
import 'package:notes/screens/home/home_screen.dart';
import 'package:notes/screens/setup/actor_setup.dart';
import 'package:notes/screens/setup/sync_setup.dart';
import 'package:time_provider/time_provider.dart';

import 'setup_test_helpers.dart';

void main() {
  for (final actor in [false, true]) {
    for (final enabled in <bool?>[null, false, true]) {
      for (final server in [false, true]) {
        for (final group in [false, true]) {
          testWidgets('startup with actor=$actor, enabled=$enabled, '
              'server=$server, group=$group', (tester) async {
            final system = await testSystem(
              actor: actor,
              syncEnabled: enabled,
              server: server,
              group: group,
            );
            final bootstrap = _SetupBootstrap(system);
            final syncComplete =
                enabled == false || (enabled == true && server && group);
            await tester.pumpWidget(
              MyApp(
                bootstrap: bootstrap,
                applicationDirectory: () async => 'unused',
              ),
            );
            await tester.pumpAndSettle();
            expect(
              find.byType(ActorSetup),
              actor ? findsNothing : findsOneWidget,
            );
            expect(
              find.byType(SyncSetup),
              actor && !syncComplete ? findsOneWidget : findsNothing,
            );
            expect(
              find.byType(HomeScreen),
              actor && syncComplete ? findsOneWidget : findsNothing,
            );
            expect(
              bootstrap.eventInitializations,
              actor && syncComplete ? 1 : 0,
            );

            if (!actor) {
              await tester.tap(find.text('Populate from static value'));
              await tester.pump();
              await tester.tap(find.text('Continue'));
              await tester.pumpAndSettle();
            }
            if (!syncComplete) {
              expect(find.byType(SyncSetup), findsOneWidget);
              await tester.tap(find.text('Continue'));
              await tester.pumpAndSettle();
            }
            expect(find.byType(HomeScreen), findsOneWidget);
            expect(bootstrap.eventInitializations, 1);
            expect(
              bootstrap.writer,
              (await system.identities.getLocal())!.publicKey.toString(),
            );
          });
        }
      }
    }
  }

  for (final configured in [false, true]) {
    testWidgets(
      'skip persists across relaunch with configuration=$configured',
      (tester) async {
        final system = await testSystem(
          syncEnabled: null,
          server: configured,
          group: configured,
        );
        await tester.pumpWidget(
          MyApp(
            bootstrap: _SetupBootstrap(system),
            applicationDirectory: () async => 'unused',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SyncSetup), findsOneWidget);
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(await system.kv.getBool(NoteSystem.syncEnabledKey), isFalse);

        await tester.pumpWidget(
          MyApp(
            bootstrap: _SetupBootstrap(system),
            applicationDirectory: () async => 'unused',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SyncSetup), findsNothing);
        expect(find.byType(HomeScreen), findsOneWidget);
      },
    );
  }

  testWidgets('missing group preserves the server URL during setup', (
    tester,
  ) async {
    final system = await testSystem(group: false);
    await system.kv.setString(NoteSystem.serverUrlKey, 'wss://example.test');
    final bootstrap = _SetupBootstrap(system);
    await tester.pumpWidget(
      MyApp(bootstrap: bootstrap, applicationDirectory: () async => 'unused'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SyncSetup), findsOneWidget);
    expect(find.text('wss://example.test'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(bootstrap.eventInitializations, 0);
    await tester.enterText(find.widgetWithText(TextField, 'Group'), 'my-notes');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      await system.kv.getString(NoteSystem.serverUrlKey),
      'wss://example.test',
    );
    expect(await system.kv.getString(NoteSystem.groupKey), 'my-notes');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('relaunch preserves a configured group and skips setup', (
    tester,
  ) async {
    final system = await testSystem(server: false, group: false);
    await tester.pumpWidget(
      MyApp(
        bootstrap: _SetupBootstrap(system),
        applicationDirectory: () async => 'unused',
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Group'), 'my-notes');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MyApp(
        bootstrap: _SetupBootstrap(system),
        applicationDirectory: () async => 'unused',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(await system.kv.getString(NoteSystem.groupKey), 'my-notes');
  });

  testWidgets('relaunch after actor setup shows only server setup', (
    tester,
  ) async {
    final system = await testSystem(actor: false, server: false);
    await tester.pumpWidget(
      MyApp(
        bootstrap: _SetupBootstrap(system),
        applicationDirectory: () async => 'unused',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MyApp(
        bootstrap: _SetupBootstrap(system),
        applicationDirectory: () async => 'unused',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ActorSetup), findsNothing);
    expect(find.byType(SyncSetup), findsOneWidget);
  });
}

class _SetupBootstrap extends NoteBootstrap {
  final NoteSystem system;
  int eventInitializations = 0;
  String? writer;

  _SetupBootstrap(this.system)
    : super(
        logger: const NoopLogger(),
        timeProvider: FakeTimeProviderStatic.zero(),
      );

  @override
  Future<NoteSystem> initializeSystem({required String dbFilepath}) async =>
      system;

  @override
  Future<NotesApp> initialize({
    required NoteSystem system,
    required String actor,
  }) async {
    eventInitializations++;
    writer = actor;
    return super.initialize(system: system, actor: actor);
  }
}
