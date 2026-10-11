import 'package:flutter/material.dart';
import 'package:notes/screens/restart_required_screen.dart';

/// Confirms deletion of all local Notes data.
Future<void> confirmDatabaseReset(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Reset database?'),
        content: const Text(
          'This deletes all notes, event history, settings, and pairings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return;
  await RestartRequiredScreen.open(context, resetDatabase: true);
}
