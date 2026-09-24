import 'package:flutter/material.dart';
import 'package:notes/application/note_application.dart';
import 'package:notes/application/note_application_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<int> _activeNoteCount(NoteApplication application) async {
    final notes = await application.query.noteList();
    return notes.activeCount;
  }

  @override
  Widget build(BuildContext context) {
    final application = NoteApplicationProvider.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: FutureBuilder<int>(
        future: _activeNoteCount(application),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.note),
                title: const Text('Active Note Count'),
                subtitle: Text('${snapshot.data}'),
              ),
            ],
          );
        },
      ),
    );
  }
}
