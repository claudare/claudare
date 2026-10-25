/// A JSON message for peer discovery and sessions.
sealed class TransportMessage {
  const TransportMessage();

  Map<String, dynamic> toJson() => switch (this) {
    TransportMessageDiscovery() => {'type': 'discovery'},
    TransportMessageHandshake(:final sessionId) => {
      'type': 'handshake',
      'sessionId': sessionId,
    },
    TransportMessageHandshakeAck(:final sessionId) => {
      'type': 'handshakeAck',
      'sessionId': sessionId,
    },
    TransportMessageData(:final sessionId, :final data) => {
      'type': 'data',
      'sessionId': sessionId,
      'data': data,
    },
    TransportMessageKeepalive(:final sessionId) => {
      'type': 'keepalive',
      'sessionId': sessionId,
    },
    TransportMessageClose(:final sessionId) => {
      'type': 'close',
      'sessionId': sessionId,
    },
  };

  /// Rejects malformed JSON values with [FormatException].
  factory TransportMessage.fromJson(Object? value) {
    try {
      final json = value as Map<String, dynamic>;
      if (json['type'] == 'discovery') {
        return const TransportMessageDiscovery();
      }
      final sessionId = json['sessionId'] as String;
      if (sessionId.isEmpty) {
        throw const FormatException('Transport sessionId must be nonempty');
      }
      return switch (json['type']) {
        'handshake' => TransportMessageHandshake(sessionId),
        'handshakeAck' => TransportMessageHandshakeAck(sessionId),
        'data' => TransportMessageData(
          sessionId: sessionId,
          data: json['data'] as String,
        ),
        'keepalive' => TransportMessageKeepalive(sessionId),
        'close' => TransportMessageClose(sessionId),
        _ => throw FormatException(
          'Unknown transport message type: ${json['type']}',
        ),
      };
    } on TypeError catch (_, stack) {
      Error.throwWithStackTrace(
        const FormatException('Invalid transport message fields'),
        stack,
      );
    }
  }
}

/// Requests discovery of peers through a broadcast.
class TransportMessageDiscovery extends TransportMessage {
  const TransportMessageDiscovery();
}

/// Proposes a fresh peer session.
class TransportMessageHandshake extends TransportMessage {
  final String sessionId;

  const TransportMessageHandshake(this.sessionId);
}

/// Accepts the session proposed by [TransportMessageHandshake].
class TransportMessageHandshakeAck extends TransportMessage {
  final String sessionId;

  const TransportMessageHandshakeAck(this.sessionId);
}

/// Carries an unchanged String payload for one session.
class TransportMessageData extends TransportMessage {
  final String sessionId;
  final String data;

  const TransportMessageData({required this.sessionId, required this.data});
}

/// Signals activity in one session without requesting a reply.
class TransportMessageKeepalive extends TransportMessage {
  final String sessionId;

  const TransportMessageKeepalive(this.sessionId);
}

/// Signals that a peer session has closed.
class TransportMessageClose extends TransportMessage {
  final String sessionId;

  const TransportMessageClose(this.sessionId);
}
