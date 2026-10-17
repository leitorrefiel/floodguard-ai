import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:floodguard/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('Home navigation preserves the authentication root route', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Authentication root')),
      ),
    );

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Text('Alerts route'),
          bottomNavigationBar: AppBottomNav(index: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Authentication root'), findsOneWidget);
    expect(find.text('Alerts route'), findsNothing);
    expect(navigatorKey.currentState!.canPop(), isFalse);
  });
}
