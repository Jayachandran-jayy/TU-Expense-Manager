import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tu_expense_tracker/src/mobile/screens/contribute_sample_dialog.dart';

void main() {
  const rawSms = 'Spent Rs.350 on HDFC Card ending 4321 at Blinkit. Bal: Rs 12,000.00.';

  final Finder githubButton = find.ancestor(
    of: find.text('Post on GitHub (public, replies possible)'),
    matching: find.bySubtype<OutlinedButton>(),
  );

  Future<void> pumpDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

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

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
  }

  testWidgets('ContributeSampleDialog renders the send guide, masks PII, and gates sending on opt-in', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await pumpDialog(tester);

    expect(find.text('Contribute SMS Format'), findsOneWidget);
    expect(find.text('Help train local AI & expand code-baked RAG'), findsOneWidget);

    expect(find.text('Simple 3-Step Contribution Guide'), findsOneWidget);
    expect(find.textContaining('Inspect Redactions'), findsOneWidget);
    expect(find.textContaining('1-Tap Send'), findsOneWidget);
    expect(find.textContaining('Opt-in only'), findsOneWidget);

    final textField = tester.widget<TextField>(find.byType(TextField).first);
    expect(textField.controller?.text, contains('Card ending *XXXX'));
    expect(textField.controller?.text, contains('Bal: Rs [MASKED]'));

    // Not opted in: the send button is disabled and says why.
    expect(find.text('Sharing is off in Settings'), findsOneWidget);
    final FilledButton send = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(send.onPressed, isNull);
    final OutlinedButton github = tester.widget<OutlinedButton>(githubButton);
    expect(github.onPressed, isNull);
    expect(find.text('Post on GitHub (public, replies possible)'), findsOneWidget);
    expect(find.text('Copy Sanitized JSON'), findsOneWidget);
  });

  testWidgets('ContributeSampleDialog enables sending once the user has opted in', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{'ledger.contribute_enabled': true});
    await pumpDialog(tester);

    expect(find.text('Send anonymously'), findsOneWidget);
    final FilledButton send = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(send.onPressed, isNotNull);
    final OutlinedButton github = tester.widget<OutlinedButton>(githubButton);
    expect(github.onPressed, isNotNull);
  });
}
