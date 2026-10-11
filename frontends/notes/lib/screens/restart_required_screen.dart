import 'package:flutter/material.dart';
import 'package:notes/application/note_bootstrap.dart';
import 'package:notes/application/note_bootstrap_provider.dart';
import 'package:restart_app/restart_app.dart';
import 'package:support_directory/support_directory.dart';

/// Prepares Notes for restart, optionally deleting local data.
class RestartRequiredScreen extends StatefulWidget {
  final NoteBootstrap bootstrap;
  final SupportDirectory supportDirectory;
  final bool resetDatabase;

  const RestartRequiredScreen({
    super.key,
    required this.bootstrap,
    required this.supportDirectory,
    this.resetDatabase = false,
  });

  /// Opens the restart screen and removes the previous navigation history.
  static Future<void> open(BuildContext context, {bool resetDatabase = false}) {
    final resources = NoteBootstrapProvider.of(context);
    return Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute(
        builder: (context) => RestartRequiredScreen(
          bootstrap: resources.bootstrap,
          supportDirectory: resources.supportDirectory,
          resetDatabase: resetDatabase,
        ),
      ),
      (route) => false,
    );
  }

  @override
  State<RestartRequiredScreen> createState() => _RestartRequiredScreenState();
}

class _RestartRequiredScreenState extends State<RestartRequiredScreen> {
  bool _preparing = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      await widget.bootstrap.close();
      if (widget.resetDatabase) await widget.supportDirectory.delete();
      if (mounted) setState(() => _preparing = false);
    } catch (error, stackTrace) {
      widget.bootstrap.logger.error(
        'Failed to prepare Notes for restart',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(() {
          _preparing = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error == null
                    ? 'Restart required'
                    : widget.resetDatabase
                    ? 'Could not reset Notes'
                    : 'Could not prepare Notes for restart',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_preparing)
                const CircularProgressIndicator()
              else if (_error != null)
                SelectableText('$_error', textAlign: TextAlign.center)
              else ...[
                const Text(
                  'The application needs to be restarted due to a database '
                  'change.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (Theme.of(context).platform != TargetPlatform.iOS)
                  FilledButton(
                    onPressed: () =>
                        Restart.restartApp(mode: RestartMode.process),
                    child: const Text('Restart now'),
                  )
                else
                  const Text(
                    'Close and reopen the application to continue.',
                    textAlign: TextAlign.center,
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
