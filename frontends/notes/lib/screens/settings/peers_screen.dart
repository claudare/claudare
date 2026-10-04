import 'dart:async';

import 'package:claudare_crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:sync/sync.dart';

/// Adds and removes saved peer identities without editing existing peers.
class PeersScreen extends StatefulWidget {
  final ActorIdentityStore identities;

  const PeersScreen({super.key, required this.identities});

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  final _publicKey = TextEditingController();
  final _staticValue = TextEditingController(text: '0');
  List<PeerActorIdentity> _peers = [];
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _inputError;
  String? _staticError;
  String? _saveError;

  bool get _available => !_loading && !_saving && _loadError == null;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final peers = await widget.identities.allPeers();
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _loading = false;
      });
    } on Exception {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load peers. Try again.';
        });
      }
    }
  }

  void _populateStatic() {
    final value = int.tryParse(_staticValue.text.trim());
    setState(() {
      _staticError = value == null ? 'Enter a valid integer' : null;
      if (value != null) {
        _publicKey.text = PublicKey.staticValue(value).toString();
        _inputError = null;
        _saveError = null;
      }
    });
  }

  Future<void> _add() async {
    if (!_available) return;
    PublicKey key;
    try {
      key = PublicKey.fromString(_publicKey.text.trim());
    } on FormatException {
      setState(() => _inputError = 'Enter a valid public key');
      return;
    } on ArgumentError {
      // PublicKey rejects decoded input that is not exactly 32 bytes.
      setState(() => _inputError = 'Enter a valid public key');
      return;
    }
    if (_peers.any((peer) => peer.publicKey == key)) {
      setState(() => _inputError = 'Peer already exists');
      return;
    }
    await _persist(
      () => widget.identities.addPeer(PeerActorIdentity(publicKey: key)),
      success: 'Peer added',
      failure: 'Could not add peer. Try again.',
      clearInput: true,
    );
  }

  Future<void> _remove(PublicKey key) => _persist(
    () => widget.identities.deletePeer(key),
    success: 'Peer removed',
    failure: 'Could not remove peer. Try again.',
  );

  Future<void> _persist(
    Future<void> Function() save, {
    required String success,
    required String failure,
    bool clearInput = false,
  }) async {
    if (!_available) return;
    setState(() {
      _saving = true;
      _saveError = null;
      _inputError = null;
    });
    try {
      await save();
    } on Exception {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = failure;
        });
      }
      return;
    }
    if (!mounted) return;
    if (clearInput) _publicKey.clear();
    await _load();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(success), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    _publicKey.dispose();
    _staticValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Peers')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Saved peers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_loading)
            const Text('Loading…')
          else if (_loadError != null) ...[
            Text(_loadError!),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ] else if (_peers.isEmpty)
            const Text('No peers')
          else
            for (final peer in _peers)
              ListTile(
                key: ValueKey(peer.publicKey),
                contentPadding: EdgeInsets.zero,
                title: SelectableText(peer.publicKey.toString()),
                trailing: TextButton(
                  onPressed: _available ? () => _remove(peer.publicKey) : null,
                  child: const Text('Remove'),
                ),
              ),
          if (_saveError != null) Text(_saveError!),
          const SizedBox(height: 24),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Add peer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter a peer public key, or populate one from a static value.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _publicKey,
                    enabled: _available,
                    onChanged: (_) => setState(() {
                      _inputError = null;
                      _saveError = null;
                    }),
                    decoration: InputDecoration(
                      labelText: 'Public key',
                      border: const OutlineInputBorder(),
                      errorText: _inputError,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Use a static value',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _staticValue,
                    enabled: _available,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    onChanged: (_) => setState(() => _staticError = null),
                    decoration: InputDecoration(
                      labelText: 'Static integer value',
                      border: const OutlineInputBorder(),
                      errorText: _staticError,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _available ? _populateStatic : null,
                    child: const Text('Populate from static value'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _available ? _add : null,
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
