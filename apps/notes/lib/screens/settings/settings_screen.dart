import 'package:flutter/material.dart';
import 'package:notes/application/application.dart';
import 'package:notes/application/application_provider.dart';
import 'package:notes/read_model/resolved_note/resolved_note_read_model.dart';

class SettingsData {
  final int eventCount;
  final int noteCount;

  const SettingsData({required this.eventCount, required this.noteCount});
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<SettingsData> fetchSettings(Application application) async {
    final dbRes = await application.eventStore.getStatistics();

    // quick and dirty :)
    final allNotes = await application.notesRuntime.resolvedNoteReadModel.query(
      ResolvedNoteQueryCategory.notTrashed,
      ResolvedNoteQueryOrder.createdAtAscending,
    );

    return SettingsData(
      eventCount: dbRes.eventCount,
      noteCount: allNotes.length,
    );
  }

  Future<void> _resetApplication(Application application) async {
    await application.eventStore.reset();
    await application.notesRuntime.recreateProjections();
  }

  Future<void> _reloadAllProjections(Application application) async {
    await application.notesRuntime.recreateProjections();
  }

  @override
  Widget build(BuildContext context) {
    final application = ApplicationProvider.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: FutureBuilder(
        future: fetchSettings(application),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data!;

          return ListView(
            children: [
              ListTile(
                leading: Icon(Icons.access_alarm),
                title: const Text('Event Count'),
                subtitle: Text('${data.eventCount}'),
              ),
              ListTile(
                leading: Icon(Icons.note),
                title: const Text('Note Count'),
                subtitle: Text('${data.noteCount}'),
              ),
              ListTile(
                leading: Icon(Icons.refresh),
                title: const Text('Rerun projections'),
                onTap: () async {
                  await _reloadAllProjections(application);
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Projections were reloaded')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.delete),
                title: const Text('Reset database'),
                onTap: () async {
                  await _resetApplication(application);
                  if (!context.mounted) {
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Database reset successfully'),
                    ),
                  );
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
