import 'package:flutter/material.dart';
import 'package:notes_app_v0/controller_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          SettingsItem(
            icon: Icons.brightness_4,
            title: Text('Theme'),
            trailing: DropdownButton<String>(
              value: 'Light',
              items:
                  ['Light', 'Dark'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
              onChanged: (String? newValue) {
                // Handle theme change
              },
            ),
          ),
          // place a button to reset app
          SettingsItem(
            icon: Icons.restart_alt,
            title: Text('Reset App'),
            trailing: IconButton(
              icon: Icon(Icons.arrow_forward),
              onPressed: () {
                final controller = ControllerProvider.of(context);
                controller.resetApp();
              },
            ),
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
