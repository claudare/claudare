import 'package:cqrs/cqrs.dart';
import 'package:test/test.dart';

void main() {
  test('carries a command rejection message', () {
    const exception = CommandException('not allowed');

    expect(exception.message, 'not allowed');
  });
}
