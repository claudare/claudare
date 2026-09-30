import 'package:claudare_crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:sync/sync.dart';

/// Chooses and persists the installation's local actor identity.
class ActorSetup extends StatefulWidget {
  final ActorIdentityStore identities;
  final ValueChanged<LocalActorIdentity> onSaved;

  const ActorSetup({
    super.key,
    required this.identities,
    required this.onSaved,
  });

  @override
  State<ActorSetup> createState() => _ActorSetupState();
}

class _ActorSetupState extends State<ActorSetup> {
  final _staticValue = TextEditingController(text: '0');
  PublicKey _key = PublicKey.secureRandom();
  String? _inputError;
  String? _saveError;
  bool _saving = false;

  @override
  void dispose() {
    _staticValue.dispose();
    super.dispose();
  }

  void _populateStatic() {
    final value = int.tryParse(_staticValue.text.trim());
    setState(() {
      _inputError = value == null ? 'Enter a valid integer' : null;
      if (value != null) _key = PublicKey.staticValue(value);
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final identity = await widget.identities.setLocal(
        LocalActorIdentity(publicKey: _key),
      );
      if (mounted) widget.onSaved(identity);
    } on Exception {
      if (mounted) {
        setState(() {
          _saveError = 'Could not save actor identity. Try again.';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Actor setup')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Local public key'),
        SelectableText(_key.toString()),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: _saving
              ? null
              : () => setState(() => _key = PublicKey.secureRandom()),
          child: const Text('Generate random'),
        ),
        TextField(
          controller: _staticValue,
          enabled: !_saving,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: InputDecoration(
            labelText: 'Static integer value',
            errorText: _inputError,
          ),
        ),
        OutlinedButton(
          onPressed: _saving ? null : _populateStatic,
          child: const Text('Populate from static value'),
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
