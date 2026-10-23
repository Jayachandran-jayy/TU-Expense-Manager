// VM only: Drives the mobile add-transaction screen, which imports dart:io.
@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/main.dart';
import 'package:tu_expense_tracker/src/mobile/screens/add_transaction_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const categories = <ExpenseCategory>[
    ExpenseCategory(id: 1, name: 'Uncategorized'),
    ExpenseCategory(id: 2, name: 'Food'),
    ExpenseCategory(id: 3, name: 'Shopping'),
  ];

  const merchants = <String>['SWIGGY', 'AMAZON INDIA'];
  const paymentTypes = <String>['HDFC Bank Card 6824', 'HDFC Bank Card 8174'];

  group('PasteTransactionDialog', () {
    testWidgets('shows validation error when text is empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasteTransactionDialog(
              categories: categories,
              merchants: merchants,
              paymentTypes: paymentTypes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Paste transaction'), findsOneWidget);
      expect(find.text('Parse'), findsOneWidget);

      // Tap Parse without entering text
      await tester.tap(find.text('Parse'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please paste SMS or email text first.'),
        findsOneWidget,
      );
    });

    testWidgets('shows error when text is not a transaction and no AI available',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PasteTransactionDialog(
              categories: categories,
              merchants: merchants,
              paymentTypes: paymentTypes,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'Hello friend, are we still meeting today?',
      );
      await tester.tap(find.text('Parse'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not extract transaction details'),
        findsOneWidget,
      );
    });

    testWidgets('parses valid bank SMS and transitions to AddTransactionScreen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const smsText =
          'Spent Rs.100.00 On HDFC Bank Card 6824 At SWIGGY On 2026-08-22:10:00:00.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const PasteTransactionDialog(
                        categories: categories,
                        merchants: merchants,
                        paymentTypes: paymentTypes,
                      ),
                    );
                  },
                  child: const Text('Open Paste Dialog'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open dialog
      await tester.tap(find.text('Open Paste Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Paste transaction'), findsOneWidget);

      // Enter SMS text
      await tester.enterText(find.byType(TextField), smsText);
      await tester.tap(find.text('Parse'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed, and AddTransactionScreen should be pushed
      expect(find.byType(PasteTransactionDialog), findsNothing);
      expect(find.byType(AddTransactionScreen), findsOneWidget);

      // Verify prefilled values
      expect(find.text('100.00'), findsOneWidget);
      expect(find.text('SWIGGY'), findsOneWidget);
    });

    testWidgets('parses valid bank Email and transitions to AddTransactionScreen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const emailText = '''
        Dear Customer,
        Thank you for using your HDFC Bank Credit Card ending in 8174 for INR 1,599.00 at AMAZON INDIA on 22-09-2026 14:30:15.
        Auth code: 987654.
        Available limit: INR 1,50,000.
      ''';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const PasteTransactionDialog(
                        categories: categories,
                        merchants: merchants,
                        paymentTypes: paymentTypes,
                      ),
                    );
                  },
                  child: const Text('Open Paste Dialog'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Paste Dialog'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), emailText);
      await tester.tap(find.text('Parse'));
      await tester.pumpAndSettle();

      expect(find.byType(PasteTransactionDialog), findsNothing);
      expect(find.byType(AddTransactionScreen), findsOneWidget);

      // Verify prefilled values from email
      expect(find.text('1599.00'), findsOneWidget);
      expect(find.text('AMAZON INDIA'), findsOneWidget);
    });
  });
}
