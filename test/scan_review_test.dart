import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/main.dart';

class FakeScanDatabase implements AppDatabase {
  final List<ParsedSms> inserted = <ParsedSms>[];
  final List<int> deletedUnadded = <int>[];

  @override
  Future<int> insertParsed(ParsedSms sms) async {
    inserted.add(sms);
    return inserted.length;
  }

  @override
  Future<void> deleteUnaddedSms(int id) async {
    deletedUnadded.add(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final ParsedSms sms1 = ParsedSms(
    amount: 350.0,
    merchant: 'SWIGGY',
    paymentType: 'HDFC Card 1234',
    date: DateTime(2026, 8, 15, 12, 30),
    direction: TxnDirection.debit,
    reference: 'REF123',
  );

  final ParsedSms sms2 = ParsedSms(
    amount: 1200.0,
    merchant: 'SALARY DEPOSIT',
    paymentType: 'HDFC Account 5678',
    date: DateTime(2026, 8, 15, 9, 0),
    direction: TxnDirection.credit,
    reference: 'SAL456',
  );

  group('ScanReviewScreen', () {
    testWidgets('renders empty state when candidate list is empty',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ScanReviewScreen(
            candidates: <CandidateTransaction>[],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No new transactions to review'), findsOneWidget);
      expect(
        find.text('All SMS messages in your inbox are already recorded.'),
        findsOneWidget,
      );
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('renders candidates, handles item toggle and batch commit',
        (WidgetTester tester) async {
      final fakeDb = FakeScanDatabase();
      bool addedCallbackFired = false;

      final candidates = <CandidateTransaction>[
        CandidateTransaction(
          parsed: sms1,
          rawBody: 'Spent Rs.350 at Swiggy on card 1234',
          unaddedSmsId: 42,
          selected: true,
        ),
        CandidateTransaction(
          parsed: sms2,
          rawBody: 'Credited Rs.1200 salary',
          selected: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: ScanReviewScreen(
            candidates: candidates,
            database: fakeDb,
            onAdded: () => addedCallbackFired = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify initial rendering
      expect(find.text('Found Transactions'), findsOneWidget);
      expect(find.text('SWIGGY'), findsOneWidget);
      expect(find.text('SALARY DEPOSIT'), findsOneWidget);
      expect(find.text('- ₹350.00'), findsOneWidget);
      expect(find.text('+ ₹1,200.00'), findsOneWidget);
      expect(find.text('2 of 2 selected · Total: ₹1,550.00'), findsOneWidget);
      expect(find.text('Add 2 transactions (₹1,550.00)'), findsOneWidget);

      // Test "Select All / Deselect All" toggle in AppBar
      expect(find.text('Deselect all'), findsOneWidget);
      await tester.tap(find.text('Deselect all'));
      await tester.pumpAndSettle();

      expect(find.text('0 of 2 selected · Total: ₹0.00'), findsOneWidget);
      // Button is disabled when 0 selected
      final filledButton = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(filledButton.onPressed, isNull);

      // Tap select all
      expect(find.text('Select all'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      expect(find.text('2 of 2 selected · Total: ₹1,550.00'), findsOneWidget);

      // Deselect the second candidate (SALARY DEPOSIT)
      await tester.tap(find.text('SALARY DEPOSIT'));
      await tester.pumpAndSettle();

      expect(find.text('1 of 2 selected · Total: ₹350.00'), findsOneWidget);
      expect(find.text('Add 1 transaction (₹350.00)'), findsOneWidget);

      // Tap Add button to commit selected
      await tester.tap(find.text('Add 1 transaction (₹350.00)'));
      await tester.pumpAndSettle();

      expect(fakeDb.inserted.length, 1);
      expect(fakeDb.inserted[0].merchant, 'SWIGGY');
      expect(fakeDb.deletedUnadded, <int>[42]);
      expect(addedCallbackFired, isTrue);
    });
  });
}
