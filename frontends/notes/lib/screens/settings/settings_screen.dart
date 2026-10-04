import 'dart:async';

import 'package:flutter/material.dart';
import 'package:notes/application/event_store_provider.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/application/note_system_provider.dart';
import 'package:notes/screens/confirm_database_reset.dart';

/// Displays saved device and sync details, statistics, and database reset.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final application = NotesAppProvider.of(context);
    final eventStoreProvider = EventStoreProvider.of(context);
    final system = NoteSystemProvider.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: FutureBuilder<_SettingsData>(
        key: ValueKey((system, application)),
        future: _SettingsData.load(application, system),
        builder: (context, snapshot) {
          String display(String? value) {
            if (snapshot.connectionState != ConnectionState.done) {
              return 'Loading…';
            }
            if (snapshot.hasError) return 'Could not load settings';
            return value ?? 'Not configured';
          }

          final data = snapshot.data;
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.key),
                title: const Text('This device actor key'),
                subtitle: SelectableText(display(data?.actor)),
              ),
              ListTile(
                leading: const Icon(Icons.group),
                title: const Text('Group'),
                subtitle: SelectableText(display(data?.group)),
              ),
              ListTile(
                leading: const Icon(Icons.dns),
                title: const Text('Server URL'),
                subtitle: SelectableText(display(data?.serverUrl)),
              ),
              ListTile(
                leading: const Icon(Icons.note),
                title: const Text('Active Note Count'),
                subtitle: Text(
                  display(data?.statistics.activeCount.toString()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.event),
                title: const Text('Event Count'),
                subtitle: Text(display(data?.statistics.eventCount.toString())),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever),
                title: const Text('Reset database'),
                onTap: () async {
                  final restart = await confirmDatabaseReset(context);
                  if (restart != null) {
                    await eventStoreProvider.reset(restart);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsData {
  final String actor;
  final String? group;
  final String? serverUrl;
  final StatisticsState statistics;

  const _SettingsData({
    required this.actor,
    required this.group,
    required this.serverUrl,
    required this.statistics,
  });

  static Future<_SettingsData> load(
    NotesApp application,
    NoteSystem system,
  ) async {
    final (group, serverUrl, statistics) = await (
      system.kv.get(NoteSystem.groupKey),
      system.kv.get(NoteSystem.serverUrlKey),
      application.query.statistics(),
    ).wait;
    return _SettingsData(
      actor: application.actor,
      group: group,
      serverUrl: serverUrl,
      statistics: statistics,
    );
  }
}
