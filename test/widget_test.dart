import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:floodguard/main.dart';
import 'package:floodguard/screens/login_screen.dart';

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

  testWidgets('login blocks empty and malformed credentials', (tester) async {
    var submitted = false;
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(signIn: (_, _) async => submitted = true)),
    );

    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Use at least 6 characters.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address'),
      'person@',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      '123456',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(submitted, isFalse);
  });

  testWidgets('login reports incorrect password without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          signIn: (_, _) async =>
              throw const AuthException('Invalid login credentials'),
        ),
      ),
    );
    await _enterValidCredentials(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid login credentials'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('login reports network failure and restores the form', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(signIn: (_, _) async => throw Exception('offline')),
      ),
    );
    await _enterValidCredentials(tester);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.text('Unable to connect. Please check your internet connection.'),
      findsOneWidget,
    );
    expect(find.text('Sign in'), findsOneWidget);
  });
}

Future<void> _enterValidCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Email address'),
    'person@example.com',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'correct-password',
  );
}
