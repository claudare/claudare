import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kv/kv.dart';
import 'package:notes/application/app_version.dart';
import 'package:notes/application/note_bootstrap_provider.dart';
import 'package:notes_app/notes_app.dart';
import 'package:notes/application/notes_app_provider.dart';
import 'package:notes/application/note_system.dart';
import 'package:notes/application/note_system_provider.dart';
import 'package:notes/screens/confirm_database_reset.dart';
import 'package:notes/screens/settings/peers_screen.dart';
import 'package:notes/screens/settings/replication_screen.dart';
import 'package:notes/screens/settings/transport_settings_screen.dart';
import 'package:support_directory/support_directory.dart';

/// Displays device identity, sync settings, diagnostics, and database controls.
class SystemSettingsScreen extends StatelessWidget {
  const SystemSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final application = NotesAppProvider.of(context);
    final system = NoteSystemProvider.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('System')),
      body: _SettingsBody(
        key: ValueKey((system, application)),
        application: application,
        system: system,
        supportDirectory: NoteBootstrapProvider.of(context).supportDirectory,
      ),
    );
  }
}

class _SettingsBody extends StatefulWidget {
  final NotesApp application;
  final NoteSystem system;
  final SupportDirectory supportDirectory;

  const _SettingsBody({
    super.key,
    required this.application,
    required this.system,
    required this.supportDirectory,
  });

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  late Future<_SettingsData> _data = _load();
  late Future<String> _supportPath = _loadSupportPath();

  Future<String> _loadSupportPath() async =>
      (await widget.supportDirectory.getDirectory()).path;

  Future<_SettingsData> _load() =>
      _SettingsData.load(widget.application, widget.system);

  @override
  void didUpdateWidget(_SettingsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _data = _load();
    if (widget.supportDirectory != oldWidget.supportDirectory) {
      _supportPath = _loadSupportPath();
    }
  }

  Future<void> _openTransport(_SettingsData data) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => TransportSettingsScreen(
          kv: widget.system.kv,
          initialEnabled: data.enabled,
          initialServerUrl: data.serverUrl,
          initialGroup: data.group,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  Future<void> _openPeers() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => PeersScreen(identities: widget.system.identities),
      ),
    );
    if (mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_SettingsData>(
    future: _data,
    builder: (context, snapshot) {
      String display(String? value) {
        if (snapshot.connectionState != ConnectionState.done) {
          return 'Loading…';
        }
        if (snapshot.hasError) return 'Could not load settings';
        return value ?? 'Not configured';
      }

      final data = snapshot.data;
      return ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('This device actor key'),
            subtitle: SelectableText(display(data?.actor)),
          ),
          ListTile(
            leading: const Icon(Icons.group),
            title: const Text('Peers'),
            subtitle: Text(display(data?.peerCount.toString())),
            onTap:
                snapshot.connectionState == ConnectionState.done &&
                    !snapshot.hasError &&
                    data != null
                ? _openPeers
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.dns),
            title: const Text('Transport'),
            subtitle: Text(
              display(
                data == null
                    ? null
                    : data.enabled
                    ? '${data.serverUrl ?? ''} @ ${data.group ?? ''}'
                    : 'Disabled',
              ),
            ),
            onTap:
                snapshot.connectionState == ConnectionState.done &&
                    !snapshot.hasError &&
                    data != null
                ? () => _openTransport(data)
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Replication'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (context) => const ReplicationScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Event Count'),
            subtitle: Text(display(data?.eventCount.toString())),
          ),
          ListTile(
            leading: const Icon(Icons.terminal),
            title: const Text('Command Count'),
            subtitle: Text(display(data?.commandCount.toString())),
          ),
          FutureBuilder<String>(
            future: _supportPath,
            builder: (context, snapshot) => ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Support directory'),
              subtitle: SelectableText(
                snapshot.connectionState != ConnectionState.done
                    ? 'Loading…'
                    : snapshot.hasError
                    ? 'Could not load support directory'
                    : snapshot.data!,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: const Text('Reset database'),
            onTap: () => confirmDatabaseReset(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App version'),
            subtitle: SelectableText(appVersionLabel()),
          ),
        ],
      );
    },
  );
}

class _SettingsData {
  final String actor;
  final int peerCount;
  final int eventCount;
  final int commandCount;
  final bool enabled;
  final String? group;
  final String? serverUrl;

  const _SettingsData({
    required this.actor,
    required this.peerCount,
    required this.eventCount,
    required this.commandCount,
    required this.enabled,
    required this.group,
    required this.serverUrl,
  });

  static Future<_SettingsData> load(
    NotesApp application,
    NoteSystem system,
  ) async {
    final (enabled, group, serverUrl, peers, storeState) = await (
      system.kv.getBool(NoteSystem.syncEnabledKey),
      system.kv.getString(NoteSystem.groupKey),
      system.kv.getString(NoteSystem.serverUrlKey),
      system.identities.allPeers(),
      system.eventStore.getState(),
    ).wait;
    return _SettingsData(
      actor: application.actor,
      peerCount: peers.length,
      eventCount: (storeState.lastEventLogPosition ?? -1) + 1,
      commandCount: (storeState.lastCommandLogPosition ?? -1) + 1,
      enabled: enabled ?? false,
      group: group,
      serverUrl: serverUrl,
    );
  }
}
