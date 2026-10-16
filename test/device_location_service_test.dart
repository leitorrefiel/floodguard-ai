import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/services/device_location_service.dart';

void main() {
  test('GPS timeout is converted to a user-safe location error', () {
    final error = locationExceptionForPositionError(
      TimeoutException('position timed out'),
    );

    expect(error.message, contains('GPS location timed out'));
  });
}
