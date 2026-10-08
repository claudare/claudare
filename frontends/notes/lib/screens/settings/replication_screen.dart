import 'package:flutter/material.dart';
import 'package:notes/application/note_sync_provider.dart';
import 'package:sync/sync.dart';

/// Displays live diagnostics for this application's replication runtime.
class ReplicationScreen extends StatelessWidget {
  const ReplicationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final runtime = NoteSyncProvider.maybeOf(context);
    final coordinator = runtime?.coordinator;
    return Scaffold(
      appBar: AppBar(title: const Text('Replication')),
      body: coordinator == null
          ? ListView(
              children: [
                ListTile(
                  title: const Text('Status'),
                  subtitle: Text(runtime?.unavailableReason ?? 'Disabled'),
                ),
              ],
            )
          : StreamBuilder<SyncSnapshot>(
              key: ObjectKey(coordinator),
              stream: coordinator.changes,
              initialData: coordinator.snapshot,
              builder: (context, snapshot) {
                final data = snapshot.data!;
                final status = switch (data.connection) {
                  SyncConnectionState.idle => 'Idle',
                  SyncConnectionState.connecting => 'Connecting',
                  SyncConnectionState.connected => 'Connected',
                  SyncConnectionState.reconnecting => 'Reconnecting',
                  SyncConnectionState.closed => 'Closed',
                };
                final peers = data.activePeers.toList()..sort();
                return ListView(
                  children: [
                    ListTile(
                      title: const Text('Connection'),
                      subtitle: Text(status),
                    ),
                    const ListTile(
                      subtitle: Text(
                        'Connected describes the server connection. '
                        'It does not indicate that all notes are synchronized.',
                      ),
                    ),
                    ListTile(
                      title: const Text('Active peers'),
                      subtitle: Text(peers.length.toString()),
                    ),
                    if (peers.isEmpty)
                      const ListTile(title: Text('No active peers')),
                    for (final peer in peers)
                      ListTile(title: SelectableText(peer)),
                    ListTile(
                      title: const Text('Latest failure'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.lastFailure ?? 'None'),
                          if (data.lastFailureAt != null)
                            Text(
                              data.lastFailureAt!
                                  .toLocal()
                                  .toString()
                                  .split('.')
                                  .first,
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}
