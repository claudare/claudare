import 'package:claudare_logging/claudare_logging.dart';
import 'package:flutter/material.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/screens/confirm_database_reset.dart';

/// Displays startup progress and any initialization error.
class LoadingScreen extends StatefulWidget {
  final Future<NoteBootstrapResult> initialization;
  final Logger logger;
  final ValueChanged<NoteBootstrapResult> onReady;
  final Future<void> Function() onReset;

  const LoadingScreen({
    super.key,
    required this.initialization,
    required this.logger,
    required this.onReady,
    required this.onReset,
  });

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    _waitForInitialization();
  }

  Future<void> _waitForInitialization() async {
    try {
      final application = await widget.initialization;
      if (mounted) widget.onReady(application);
    } catch (error, stackTrace) {
      widget.logger.error('Failed to initialize Notes', error, stackTrace);
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      body: Center(
        child:
            error == null
                ? const CircularProgressIndicator()
                : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 56,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Could not open Notes',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      SelectableText('$error', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () async {
                          if (await confirmDatabaseReset(context)) {
                            await widget.onReset();
                          }
                        },
                        child: const Text('Reset database'),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}
