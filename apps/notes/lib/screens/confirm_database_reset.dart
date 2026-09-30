import 'package:flutter/material.dart';

/// Confirms deletion of all local Notes data.
Future<bool> confirmDatabaseReset(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset database?'),
        content: Text(
          Theme.of(context).platform == TargetPlatform.iOS
              ? 'This deletes all notes, event history, settings, and pairings. '
                    'Close and '
                    'reopen Notes if it does not restart automatically.'
              : 'This deletes all notes, event history, settings, and pairings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    ) ??
    false;
