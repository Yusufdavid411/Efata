import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logistics_app/features/auth/role_selection_screen.dart';
import 'package:logistics_app/features/driver/widgets/driver_status_toggle.dart';
import 'package:logistics_app/shared/theme/efata_theme.dart';

void main() {
  Widget screen(Widget child) => MaterialApp(
    theme: EfataTheme.build(Brightness.light),
    home: Scaffold(body: child),
  );

  testWidgets('Driver availability remains actionable on narrow screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    bool? changed;
    await tester.pumpWidget(
      screen(
        DriverStatusToggle(
          isOnline: false,
          canGoOnline: true,
          onChanged: (value) => changed = value,
        ),
      ),
    );
    expect(find.text('Offline'), findsOneWidget);
    await tester.tap(find.text('Go online'));
    expect(changed, isTrue);
    await tester.pumpWidget(
      screen(
        DriverStatusToggle(
          isOnline: true,
          canGoOnline: true,
          onChanged: (value) => changed = value,
        ),
      ),
    );
    expect(find.text('Receiving requests'), findsOneWidget);
    await tester.tap(find.text('Go offline'));
    expect(changed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('An unapproved driver cannot go online', (tester) async {
    await tester.pumpWidget(
      screen(
        DriverStatusToggle(
          isOnline: false,
          canGoOnline: false,
          onChanged: (_) => fail('Driver is not approved'),
        ),
      ),
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Go online'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('Passenger role opens registration without hiding Google', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: EfataTheme.build(Brightness.light),
        home: const RoleSelectionScreen(),
      ),
    );
    expect(find.text('Passenger'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    await tester.tap(find.text('Passenger'));
    await tester.pumpAndSettle();
    expect(find.text('Passenger registration'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
