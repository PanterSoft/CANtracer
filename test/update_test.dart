import 'package:cantracer/src/update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isNewer compares semver tags', () {
    expect(isNewer('v1.0.1', '1.0.0'), isTrue);
    expect(isNewer('v1.10.0', '1.9.9'), isTrue);
    expect(isNewer('2.0.0', 'v1.99.99'), isTrue);
    expect(isNewer('v1.0.0', '1.0.0'), isFalse);
    expect(isNewer('v0.9.0', '1.0.0'), isFalse);
    expect(isNewer('v1.0.0', '0.0.0'), isTrue); // unversioned dev build
  });
}
