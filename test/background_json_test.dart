import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:symphony/core/utils/background_json.dart';

void main() {
  test('small and large text decode the same as jsonDecode', () async {
    final small = jsonEncode({'a': 1});
    final large = jsonEncode([for (var i = 0; i < 5000; i++) {'id': 'song $i', 'plays': i}]);
    expect(large.length, greaterThan(64 * 1024), reason: 'goes to the background isolate');

    expect(await decodeJsonInBackground(small), jsonDecode(small));
    expect(await decodeJsonInBackground(large), jsonDecode(large));
    await expectLater(decodeJsonInBackground('{nope' * 20000), throwsFormatException);
  });
}
