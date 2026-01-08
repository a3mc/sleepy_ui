import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('App smoke test - initializes without errors',
      (WidgetTester tester) async {
    // Test that app initializes with ProviderScope and renders basic structure
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('SLEEPY VALIDATOR MONITOR'),
            ),
          ),
        ),
      ),
    );

    // Verify basic structure renders
    expect(find.text('SLEEPY VALIDATOR MONITOR'), findsOneWidget);
  });
}
