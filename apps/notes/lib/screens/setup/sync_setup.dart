import 'package:flutter/material.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/note_system.dart';

/// Configures the replication server and group without opening a connection.
class SyncSetup extends StatefulWidget {
  final Kv kv;
  final void Function(String serverUrl, String group) onSaved;
  final String initialServerUrl;
  final String initialGroup;

  const SyncSetup({
    super.key,
    required this.kv,
    required this.onSaved,
    this.initialServerUrl = 'ws://localhost:7000',
    this.initialGroup = '0',
  });

  @override
  State<SyncSetup> createState() => _SyncSetupState();
}

class _SyncSetupState extends State<SyncSetup> {
  late final _url = TextEditingController(text: widget.initialServerUrl);
  late final _group = TextEditingController(text: widget.initialGroup);
  String? _inputError;
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _url.dispose();
    _group.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _url.text.trim();
    final group = _group.text;
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
      await widget.kv.setAll([
        KeyValue(key: NoteSystem.serverUrlKey, value: value),
        KeyValue(key: NoteSystem.groupKey, value: group),
      ]);
      if (mounted) widget.onSaved(value, group);
    } on Exception {
      if (mounted) {
        setState(() {
          _saveError = 'Could not save sync settings. Try again.';
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
        TextField(
          controller: _group,
          enabled: !_saving,
          decoration: const InputDecoration(labelText: 'Group'),
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
