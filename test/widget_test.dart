import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floodguard/main.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'sb_publishable_local_widget_test_only',
    );
  });

  testWidgets('FloodGuard unauthenticated app renders sign-in', (tester) async {
    await tester.pumpWidget(const FloodGuardApp());

    expect(find.text('FloodGuard AI'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.text('Sign in to access your flood-preparedness dashboard.'),
      findsOneWidget,
    );
  });
}
