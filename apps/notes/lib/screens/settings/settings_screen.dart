import 'package:cqrs/cqrs.dart';
import 'package:flutter/material.dart';
import 'package:notes/application/event_store_provider.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';
import 'package:notes/screens/confirm_database_reset.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  NoteApplication? _application;
  EventStore? _eventStore;
  Future<int>? _activeNoteCount;
  Future<GetStatisticsResult>? _statistics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final application = NoteApplicationProvider.of(context);
    final eventStore = EventStoreProvider.of(context).eventStore;
    if (_application != application) {
      _application = application;
      _activeNoteCount = application.query.noteList().then(
        (notes) => notes.activeCount,
      );
    }
    if (_eventStore != eventStore) {
      _eventStore = eventStore;
      _statistics = eventStore.getStatistics();
    }
  }

  @override
  Widget build(BuildContext context) {
    final reset = EventStoreProvider.of(context).reset;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          FutureBuilder<int>(
            future: _activeNoteCount,
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
            future: _statistics,
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
              if (await confirmDatabaseReset(context)) await reset();
            },
          ),
        ],
      ),
    );
  }
}
