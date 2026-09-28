class ProxyMessage {
  final String actor;
  final String data;

  const ProxyMessage({required this.actor, required this.data});

  Map<String, dynamic> toJson() => {'actor': actor, 'data': data};

  factory ProxyMessage.fromJson(Map<String, dynamic> json) =>
      ProxyMessage(actor: json['actor'], data: json['data']);
}
