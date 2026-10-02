/// A direct or broadcast payload passed through the proxy.
sealed class ProxyMessage {
  const ProxyMessage();

  Map<String, dynamic> toJson() => switch (this) {
    ProxyDirectMessage(:final actor, :final data) => {
      'type': 'direct',
      'actor': actor,
      'data': data,
    },
    ProxyBroadcastMessage(:final group, :final data) => {
      'type': 'broadcast',
      'group': group,
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
  final String group;
  final String data;

  const ProxyBroadcastMessage({required this.group, required this.data});

  factory ProxyBroadcastMessage.fromJson(Map<String, dynamic> json) =>
      ProxyBroadcastMessage(group: json['group'], data: json['data']);
}

/// Connection initialization carried in HTTP headers.
class ProxyInit {
  /// the public key of the connecting app
  final String actor;

  /// The group it belongs to. Group routing is not implemented.
  final String group;

  const ProxyInit({required this.actor, required this.group});

  Map<String, String> toHeaders() => {
    'claudare-actor': actor,
    'claudare-group': group,
  };

  factory ProxyInit.fromHeaders(Map<String, String> headers) {
    final actor = headers['claudare-actor'];
    final group = headers['claudare-group'];
    if (actor == null ||
        actor.trim().isEmpty ||
        group == null ||
        group.trim().isEmpty) {
      throw const FormatException('Actor and group headers are required');
    }
    return ProxyInit(actor: actor, group: group);
  }
}
