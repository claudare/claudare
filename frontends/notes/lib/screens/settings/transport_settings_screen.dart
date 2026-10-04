import 'package:flutter/material.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/screens/settings/transport_health_check.dart';

/// Edits saved transport settings and checks server availability.
class TransportSettingsScreen extends StatefulWidget {
  final Kv kv;
  final bool initialEnabled;
  final String? initialServerUrl;
  final String? initialGroup;
  final Future<bool> Function(Uri) testConnection;

  TransportSettingsScreen({
    super.key,
    required this.kv,
    this.initialEnabled = false,
    this.initialServerUrl,
    this.initialGroup,
    Future<bool> Function(Uri)? testConnection,
  }) : testConnection = testConnection ?? TransportHealthCheck().call;

  @override
  State<TransportSettingsScreen> createState() =>
      _TransportSettingsScreenState();
}

class _TransportSettingsScreenState extends State<TransportSettingsScreen> {
  late final _url = TextEditingController(text: widget.initialServerUrl ?? '');
  late final _group = TextEditingController(text: widget.initialGroup ?? '');
  late bool _enabled = widget.initialEnabled;
  bool _saving = false;
  bool _testing = false;
  bool _validate = false;
  bool? _testResult;
  String? _saveError;
  int _revision = 0;

  Uri? get _serverUri {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  bool get _groupSet => _group.text.trim().isNotEmpty;
  bool get _configured => _serverUri != null && _groupSet;

  void _inputChanged(String _) {
    setState(() {
      _revision++;
      _testResult = null;
      _saveError = null;
    });
  }

  Future<void> _save() async {
    if (_saving || _testing) return;
    if (_enabled && !_configured) {
      setState(() => _validate = true);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.kv.setAll({
        NoteSystem.syncEnabledKey: _enabled,
        NoteSystem.serverUrlKey: _url.text.trim(),
        NoteSystem.groupKey: _group.text,
      });
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transport settings saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Could not save transport settings. Try again.';
        });
      }
    }
  }

  Future<void> _testConnection() async {
    if (_saving || _testing || !_configured) return;
    final revision = _revision;
    final uri = _serverUri!;
    final healthUrl = Uri(
      scheme: uri.scheme == 'ws' ? 'http' : 'https',
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '/health',
    );
    setState(() {
      _testing = true;
      _testResult = null;
    });
    bool result;
    try {
      result = await widget.testConnection(healthUrl);
    } on Exception {
      result = false;
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (revision == _revision) _testResult = result;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Transport settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SwitchListTile(
            title: const Text('Enabled'),
            value: _enabled,
            onChanged: !_saving && (_enabled || _configured)
                ? (value) => setState(() {
                    _enabled = value;
                    _validate = false;
                  })
                : null,
          ),
          TextField(
            controller: _url,
            enabled: !_saving,
            keyboardType: TextInputType.url,
            onChanged: _inputChanged,
            decoration: InputDecoration(
              labelText: 'Server URL',
              errorText: _validate && _serverUri == null
                  ? 'Enter a ws or wss URL with a host'
                  : null,
            ),
          ),
          TextField(
            controller: _group,
            enabled: !_saving,
            onChanged: _inputChanged,
            decoration: InputDecoration(
              labelText: 'Group',
              errorText: _validate && !_groupSet ? 'Enter a group' : null,
            ),
          ),
          if (_saveError != null) Text(_saveError!),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving || _testing ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: !_saving && !_testing && _configured
                ? _testConnection
                : null,
            style: _testResult == null
                ? null
                : OutlinedButton.styleFrom(
                    foregroundColor: _testResult! ? Colors.green : Colors.red,
                    side: BorderSide(
                      color: _testResult! ? Colors.green : Colors.red,
                    ),
                  ),
            child: Text(_testing ? 'Testing…' : 'Test connection'),
          ),
          if (_testResult != null)
            Text(_testResult! ? 'Connection successful' : 'Connection failed'),
        ],
      ),
    ),
  );
}
