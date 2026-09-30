import 'package:flutter/material.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/note_system.dart';

/// Configures the replication server without opening a connection.
class SyncSetup extends StatefulWidget {
  final Kv kv;
  final ValueChanged<String> onSaved;

  const SyncSetup({super.key, required this.kv, required this.onSaved});

  @override
  State<SyncSetup> createState() => _SyncSetupState();
}

class _SyncSetupState extends State<SyncSetup> {
  final _url = TextEditingController(text: 'ws://localhost:7000');
  String? _inputError;
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _url.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty) {
      setState(() => _inputError = 'Enter a ws or wss URL with a host');
      return;
    }
    setState(() {
      _inputError = null;
      _saveError = null;
      _saving = true;
    });
    try {
      await widget.kv.set(NoteSystem.serverUrlKey, value);
      if (mounted) widget.onSaved(value);
    } on Exception {
      if (mounted) {
        setState(() {
          _saveError = 'Could not save server URL. Try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sync setup')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _url,
          enabled: !_saving,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: 'Replication server URL',
            errorText: _inputError,
          ),
        ),
        if (_saveError != null) Text(_saveError!),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Continue'),
        ),
      ],
    ),
  );
}
