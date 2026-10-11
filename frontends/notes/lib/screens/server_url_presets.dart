import 'package:flutter/material.dart';

/// Selects a server URL for an editable draft.
class ServerUrlPresets extends StatelessWidget {
  final bool enabled;
  final ValueChanged<String> onSelected;

  const ServerUrlPresets({
    super.key,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      TextButton(
        onPressed: enabled ? () => onSelected('ws://localhost:7000') : null,
        child: const Text('Local Development'),
      ),
      TextButton(
        onPressed: enabled
            ? () => onSelected('wss://proxy.claudare.org')
            : null,
        child: const Text('Production'),
      ),
    ],
  );
}
