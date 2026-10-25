/// A payload or reset for one protocol session on a peer connection.
sealed class MultiplexMessage {
  /// Wire protocol name. Blank names are rejected with [ArgumentError].
  final String protocol;
  final int generation;

  MultiplexMessage({required this.protocol, required this.generation}) {
    if (protocol.trim().isEmpty) {
      throw ArgumentError.value(
        protocol,
        'protocol',
        'Protocol name must not be blank',
      );
    }
  }

  Map<String, dynamic> toJson() => switch (this) {
    MultiplexMessageData(:final data) => {
      'protocol': protocol,
      'type': 'data',
      'generation': generation,
      'data': data,
    },
    MultiplexMessageReset() => {
      'protocol': protocol,
      'type': 'reset',
      'generation': generation,
    },
  };

  /// Rejects malformed envelopes with [FormatException].
  factory MultiplexMessage.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Multiplex message must be an object');
    }
    final protocol = value['protocol'];
    if (protocol is! String || protocol.trim().isEmpty) {
      throw const FormatException(
        'Multiplex protocol must be a nonblank string',
      );
    }
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

  MultiplexMessageData({
    required super.protocol,
    required super.generation,
    required this.data,
  });
}

/// Starts a new generation of one protocol session.
class MultiplexMessageReset extends MultiplexMessage {
  MultiplexMessageReset({required super.protocol, required super.generation});
}
