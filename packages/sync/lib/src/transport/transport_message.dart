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

  factory TransportMessage.fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        'discovery' => const TransportMessageDiscovery(),
        'handshake' => TransportMessageHandshake(json['sessionId'] as String),
        'handshakeAck' => TransportMessageHandshakeAck(
          json['sessionId'] as String,
        ),
        'data' => TransportMessageData(
          sessionId: json['sessionId'] as String,
          data: json['data'] as String,
        ),
        'keepalive' => TransportMessageKeepalive(json['sessionId'] as String),
        'close' => TransportMessageClose(json['sessionId'] as String),
        _ => throw FormatException(
          'Unknown transport message type: ${json['type']}',
        ),
      };
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
