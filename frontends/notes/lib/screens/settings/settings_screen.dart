import 'package:flutter/material.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/screens/settings/system_settings_screen.dart';
import 'package:notes_app/notes_app.dart';

/// Displays app statistics and opens system settings.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final application = NotesAppProvider.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          FutureBuilder<StatisticsState>(
            key: ValueKey(application),
            future: application.query.statistics(),
            builder: (context, snapshot) {
              final count = snapshot.connectionState != ConnectionState.done
                  ? 'Loading…'
                  : snapshot.hasError
                  ? 'Could not load settings'
                  : snapshot.data!.activeCount.toString();
              return ListTile(
                leading: const Icon(Icons.note),
                title: const Text('Active Note Count'),
                subtitle: Text(count),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.build),
            title: const Text('System'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (context) => const SystemSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
