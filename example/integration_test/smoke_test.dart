import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('smoke test', ($) async {
    print('Patrol smoke test running!');
    expect(1 + 1, equals(2));
    print('Patrol smoke test passed!');
  });
}
