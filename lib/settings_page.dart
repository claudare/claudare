import 'package:flutter/material.dart';
import 'package:notes_app_v0/controller_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ControllerProvider.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          // AsyncTile(
          //   icon: Icons.folder,
          //   title: Text('Documents folder'),
          //   future: getApplicationDocumentsDirectory().then(
          //     (value) => Text(value.path),
          //   ),
          // ),
          AsyncTile(
            icon: Icons.event_note,
            title: Text('Events stored'),
            future: controller.eventCount().then(
              (value) => Text(value.toString()),
            ),
          ),
          AsyncTile(
            icon: Icons.storage,
            title: Text('Database size'),
            future: controller.allDatabaseSizes().then(
              (value) => Text(value.toString()),
            ),
          ),
          ListTile(
            leading: Icon(Icons.delete),
            title: Text('Delete all data and restart'),
            onTap: () {
              controller.deleteAllDataAndRestart();
            },
          ),
        ],
      ),
    );
  }
}

class SettingsItem extends StatelessWidget {
  const SettingsItem({
    super.key,
    required this.icon,
    required this.title,
    required this.trailing,
  });

  final IconData icon;
  final Widget title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(leading: Icon(icon), title: title, trailing: trailing);
  }
}

class AsyncTile extends StatelessWidget {
  const AsyncTile({
    super.key,
    required this.icon,
    required this.title,
    required this.future,
  });

  final IconData icon;
  final Widget title;
  final Future<Widget> future;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: title,
      trailing: FutureBuilder<Widget>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return snapshot.data!;
          } else if (snapshot.hasError) {
            return Text('Error. ${snapshot.error.toString()}');
          } else {
            return CircularProgressIndicator();
          }
        },
      ),
    );
  }
}
