/// A direct or broadcast payload passed through the proxy.
sealed class ProxyMessage {
  const ProxyMessage();

  Map<String, dynamic> toJson() => switch (this) {
    ProxyDirectMessage(:final actor, :final data) => {
      'type': 'direct',
      'actor': actor,
      'data': data,
    },
    ProxyBroadcastMessage(:final actor, :final data) => {
      'type': 'broadcast',
      'actor': actor,
      'data': data,
    },
  };

  factory ProxyMessage.fromJson(Map<String, dynamic> json) =>
      switch (json['type']) {
        'direct' => ProxyDirectMessage.fromJson(json),
        'broadcast' => ProxyBroadcastMessage.fromJson(json),
        _ => throw FormatException(
          'Unknown proxy message type: ${json['type']}',
        ),
      };
}

/// A payload addressed to an actor.
class ProxyDirectMessage extends ProxyMessage {
  final String actor;
  final String data;

  const ProxyDirectMessage({required this.actor, required this.data});

  factory ProxyDirectMessage.fromJson(Map<String, dynamic> json) =>
      ProxyDirectMessage(actor: json['actor'], data: json['data']);
}

/// A payload addressed to a group.
class ProxyBroadcastMessage extends ProxyMessage {
  final String actor;
  final String data;

  const ProxyBroadcastMessage({required this.actor, required this.data});

  factory ProxyBroadcastMessage.fromJson(Map<String, dynamic> json) =>
      ProxyBroadcastMessage(actor: json['actor'], data: json['data']);
}
