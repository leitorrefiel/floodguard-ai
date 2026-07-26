import 'package:flutter_test/flutter_test.dart';

import 'package:floodguard/main.dart';

void main() {
  testWidgets('FloodGuard home screen renders', (tester) async {
    await tester.pumpWidget(const FloodGuardApp());

    expect(find.text('FloodGuard AI'), findsOneWidget);
    expect(find.text('Moderate Risk'), findsOneWidget);
    expect(find.text('Flood Watch'), findsOneWidget);
  });
}
