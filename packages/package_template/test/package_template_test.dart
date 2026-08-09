import 'package:package_template/package_template.dart';
import 'package:test/test.dart';

void main() {
  test('returns the template package greeting', () {
    expect(packageTemplate(), 'Hello, world!');
  });
}
