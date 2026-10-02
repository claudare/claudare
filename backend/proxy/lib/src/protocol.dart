/// A payload addressed to an actor.
class ProxyMessage {
  final String actor;
  final String data;

  const ProxyMessage({required this.actor, required this.data});

  Map<String, dynamic> toJson() => {'actor': actor, 'data': data};

  factory ProxyMessage.fromJson(Map<String, dynamic> json) =>
      ProxyMessage(actor: json['actor'], data: json['data']);
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
