class CrdtStringChange {
  final String value;
  final String actor;
  final DateTime time;

  const CrdtStringChange({
    required this.value,
    required this.actor,
    required this.time,
  });

  factory CrdtStringChange.fromJson(Map<String, dynamic> json) =>
      CrdtStringChange(
        value: json['value'] as String,
        actor: json['actor'] as String,
        time: DateTime.fromMillisecondsSinceEpoch(json['time'] as int),
      );

  Map<String, dynamic> toJson() => {
    'value': value,
    'actor': actor,
    'time': time.millisecondsSinceEpoch,
  };
}
