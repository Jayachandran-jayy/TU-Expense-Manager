import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/mobile/screens/contribute_sample_dialog.dart';

void main() {
  testWidgets('ContributeSampleDialog renders 3-step guide, masks PII, and displays actions', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const rawSms = 'Spent Rs.350 on HDFC Card ending 4321 at Blinkit. Bal: Rs 12,000.00.';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () => ContributeSampleDialog.show(context, rawSms: rawSms),
                child: const Text('Open Dialog'),
              );
            },
          ),
        ),
      ),
    );

    // Tap to open bottom sheet
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify Title and Subtitle
    expect(find.text('Contribute SMS Format'), findsOneWidget);
    expect(find.text('Help train local AI & expand code-baked RAG'), findsOneWidget);

    // Verify 3-Step Guide
    expect(find.text('Simple 3-Step Contribution Guide'), findsOneWidget);
    expect(find.textContaining('Inspect Redactions'), findsOneWidget);
    expect(find.textContaining('1-Tap Submit'), findsOneWidget);
    expect(find.textContaining('Submit on GitHub'), findsOneWidget);
    expect(find.text('Read our Simple Contribution Guide on GitHub ↗'), findsOneWidget);

    // Verify PII is masked in the text field
    final textFieldFinder = find.byType(TextField).first;
    final textField = tester.widget<TextField>(textFieldFinder);
    expect(textField.controller?.text, contains('Card ending *XXXX'));
    expect(textField.controller?.text, contains('Bal: Rs [MASKED]'));

    // Verify Buttons
    expect(find.text('Contribute on GitHub ↗'), findsOneWidget);
    expect(find.text('Copy Sanitized JSON'), findsOneWidget);
  });
}
