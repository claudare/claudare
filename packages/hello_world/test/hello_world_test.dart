import 'package:hello_world/hello_world.dart';
import 'package:test/test.dart';

void main() {
  test('returns a hello world greeting', () {
    expect(helloWorld(), 'Hello, world!');
  });
}
