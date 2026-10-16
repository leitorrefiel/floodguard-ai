import 'package:flutter_test/flutter_test.dart';
import 'package:floodguard/services/notification_preference_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('preferences persist for the same authenticated user', () async {
    final preferences = await SharedPreferences.getInstance();
    final firstSession = NotificationPreferenceCache(
      preferences: preferences,
      userId: 'user-a',
    );
    await firstSession.write('floodWarnings', false);

    final restartedSession = NotificationPreferenceCache(
      preferences: await SharedPreferences.getInstance(),
      userId: 'user-a',
    );

    expect(restartedSession.read('floodWarnings'), isFalse);
  });

  test('local fallback preferences do not leak between users', () async {
    final preferences = await SharedPreferences.getInstance();
    final userA = NotificationPreferenceCache(
      preferences: preferences,
      userId: 'user-a',
    );
    final userB = NotificationPreferenceCache(
      preferences: preferences,
      userId: 'user-b',
    );
    await userA.write('nearbyHazards', false);

    expect(userA.read('nearbyHazards'), isFalse);
    expect(userB.read('nearbyHazards'), isNull);
  });

  test('local preferences remain readable without a remote request', () async {
    final preferences = await SharedPreferences.getInstance();
    final cache = NotificationPreferenceCache(
      preferences: preferences,
      userId: 'offline-user',
    );
    await cache.write('severeRainfall', true);

    expect(cache.read('severeRainfall'), isTrue);
  });
}
