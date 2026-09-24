import 'package:flutter/material.dart';

/// Confirms deletion of the local event history.
Future<bool> confirmDatabaseReset(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Reset database?'),
            content: Text(
              Theme.of(context).platform == TargetPlatform.iOS
                  ? 'This deletes all notes and event history. Close and '
                      'reopen Notes if it does not restart automatically.'
                  : 'This deletes all notes and event history.',
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
