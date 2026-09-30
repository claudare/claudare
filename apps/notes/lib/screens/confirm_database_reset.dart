import 'package:flutter/material.dart';

/// Confirms deletion of all local Notes data.
Future<bool?> confirmDatabaseReset(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
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
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: isIOS ? null : () => Navigator.of(context).pop(true),
              child: const Text('Reset and restart'),
            ),
          ],
        );
      },
    );
