import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/features/auth/login_screen.dart';

void main() {
  testWidgets('login shows Google above email sign in', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    final google = find.text('Continue with Google');
    expect(google, findsOneWidget);
    expect(
      tester.getTopLeft(google).dy,
      lessThan(tester.getTopLeft(find.text('Email address').first).dy),
    );
  });
}
