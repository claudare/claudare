import 'dart:math';

class Id {
  final String value;

  Id(this.value);

  Id.random() : this('${DateTime.now().toUtc()}+${Random().nextInt(1000000)}');

  @override
  String toString() => value;
}

String formatDateTime(DateTime dateTime) {
  return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
}
