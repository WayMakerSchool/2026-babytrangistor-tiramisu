// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:baby_cry_translator/main.dart';

void main() {
  testWidgets('Simulated input updates translation',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BabyCryTranslatorApp());

    // The screen initially waits for hardware input.
    expect(find.text('하드웨어 대기 중'), findsOneWidget);

    // Simulate a hungry cry through the test button.
    await tester.tap(find.text('배고픔(Neh)'));
    await tester.pump();

    // The received input replaces the waiting message.
    expect(find.text('하드웨어 대기 중'), findsNothing);
    expect(find.text('배고픔 (Neh)'), findsOneWidget);
  });
}
