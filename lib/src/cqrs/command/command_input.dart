abstract interface class CommandInput {
  String get kind;

  Map<String, dynamic> toJson();
}
