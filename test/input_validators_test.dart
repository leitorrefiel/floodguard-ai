import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/utils/input_validators.dart';

void main() {
  group('authentication validation', () {
    test('rejects empty and malformed email addresses', () {
      expect(validateEmailAddress(''), 'Enter a valid email address.');
      expect(validateEmailAddress('person@'), 'Enter a valid email address.');
      expect(validateEmailAddress('person@example.com'), isNull);
    });

    test('rejects empty and short passwords', () {
      expect(validatePassword(''), 'Use at least 6 characters.');
      expect(validatePassword('12345'), 'Use at least 6 characters.');
      expect(validatePassword('123456'), isNull);
    });
  });

  group('hazard report validation', () {
    test('requires a usable location label', () {
      expect(validateHazardLocation(''), 'Location is required.');
      expect(validateHazardLocation('AB'), 'Enter a more specific location.');
      expect(validateHazardLocation('Baliwag, Bulacan'), isNull);
    });

    test('enforces description boundaries', () {
      expect(validateHazardDescription('short'), isNotNull);
      expect(validateHazardDescription('x' * 300), isNull);
      expect(validateHazardDescription('x' * 301), isNotNull);
    });

    test('rejects missing, impossible, and non-finite coordinates', () {
      expect(hasValidCoordinates(null, 120.89), isFalse);
      expect(hasValidCoordinates(91, 120.89), isFalse);
      expect(hasValidCoordinates(14.95, 181), isFalse);
      expect(hasValidCoordinates(double.nan, 120.89), isFalse);
      expect(hasValidCoordinates(14.95, 120.89), isTrue);
    });
  });
}
