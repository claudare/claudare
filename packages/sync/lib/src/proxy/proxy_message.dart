/// How a [ProxyMessage] is routed through the proxy.
enum ProxyMessageType { direct, broadcast }

/// A direct or broadcast payload passed through the proxy.
class ProxyMessage {
  final ProxyMessageType type;
  final String actor;
  final String data;

  const ProxyMessage({
    required this.type,
    required this.actor,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'actor': actor,
    'data': data,
  };

  factory ProxyMessage.fromJson(Map<String, dynamic> json) => ProxyMessage(
    type: switch (json['type']) {
      'direct' => ProxyMessageType.direct,
      'broadcast' => ProxyMessageType.broadcast,
      _ => throw FormatException('Unknown proxy message type: ${json['type']}'),
    },
    actor: json['actor'],
    data: json['data'],
  );
}
