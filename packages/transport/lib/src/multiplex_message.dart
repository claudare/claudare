/// The protocol routed through a peer connection.
enum PeerProtocol { commands, blobs }

/// A payload or reset for one protocol session on a peer connection.
sealed class MultiplexMessage {
  final PeerProtocol protocol;
  final int generation;

  const MultiplexMessage({required this.protocol, required this.generation});

  Map<String, dynamic> toJson() => switch (this) {
    MultiplexMessageData(:final data) => {
      'protocol': protocol.name,
      'type': 'data',
      'generation': generation,
      'data': data,
    },
    MultiplexMessageReset() => {
      'protocol': protocol.name,
      'type': 'reset',
      'generation': generation,
    },
  };

  /// Rejects malformed envelopes with [FormatException].
  factory MultiplexMessage.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Multiplex message must be an object');
    }
    final protocol = switch (value['protocol']) {
      'commands' => PeerProtocol.commands,
      'blobs' => PeerProtocol.blobs,
      _ => throw const FormatException('Unknown multiplex protocol'),
    };
    final generation = value['generation'];
    if (generation is! int || generation < 0) {
      throw const FormatException('Multiplex generation must be nonnegative');
    }
    return switch (value['type']) {
      'reset' => MultiplexMessageReset(
        protocol: protocol,
        generation: generation,
      ),
      'data' when value['data'] is String => MultiplexMessageData(
        protocol: protocol,
        generation: generation,
        data: value['data'] as String,
      ),
      _ => throw const FormatException('Invalid multiplex message fields'),
    };
  }
}

/// Carries an unchanged string payload for one protocol session.
class MultiplexMessageData extends MultiplexMessage {
  final String data;

  const MultiplexMessageData({
    required super.protocol,
    required super.generation,
    required this.data,
  });
}

/// Starts a new generation of one protocol session.
class MultiplexMessageReset extends MultiplexMessage {
  const MultiplexMessageReset({
    required super.protocol,
    required super.generation,
  });
}
