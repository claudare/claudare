import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:notes/application/event_store_provider.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/screens/confirm_database_reset.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final application = NoteApplicationProvider.of(context);
    final eventStoreProvider = EventStoreProvider.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          FutureBuilder<int>(
            future: application.query.noteList().then(
              (notes) => notes.activeCount,
            ),
            builder:
                (context, snapshot) => ListTile(
                  leading: const Icon(Icons.note),
                  title: const Text('Active Note Count'),
                  subtitle: Text(
                    snapshot.hasError
                        ? 'Error: ${snapshot.error}'
                        : snapshot.hasData
                        ? '${snapshot.data}'
                        : 'Loading…',
                  ),
                ),
          ),
          FutureBuilder<GetStatisticsResult>(
            future: eventStoreProvider.eventStore.getStatistics(),
            builder:
                (context, snapshot) => ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Event Count'),
                  subtitle: Text(
                    snapshot.hasError
                        ? 'Error: ${snapshot.error}'
                        : snapshot.hasData
                        ? '${snapshot.data!.eventCount}'
                        : 'Loading…',
                  ),
                ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: const Text('Reset database'),
            onTap: () async {
              if (await confirmDatabaseReset(context)) {
                await eventStoreProvider.reset();
              }
            },
          ),
        ],
      ),
    );
  }
}
