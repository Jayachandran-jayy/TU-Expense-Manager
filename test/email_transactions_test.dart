import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tu_expense_tracker/src/core/email_parser.dart';
import 'package:tu_expense_tracker/src/core/models.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';
import 'package:tu_expense_tracker/src/mobile/screens/add_transaction_screen.dart';
import 'package:tu_expense_tracker/src/mobile/screens/email_transactions_screen.dart';
import 'package:tu_expense_tracker/src/mobile/services/email_service.dart';

class FakeEmailAdapter implements EmailClientAdapter {
  bool connected = false;
  List<EmailMessageItem> cannedEmails = <EmailMessageItem>[];

  @override
  Future<void> connectAndLogin({
    required String email,
    required String appPassword,
  }) async {
    if (email.contains('error')) {
      throw Exception('Invalid credentials or app password');
    }
    connected = true;
  }

  @override
  Future<List<EmailMessageItem>> fetchRecentEmails({
    int messageCount = 50,
    int days = 14,
  }) async {
    return cannedEmails;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('EmailService', () {
    test('credential management and configuration check', () async {
      final service = EmailService.instance;
      expect(await service.isConfigured(), isFalse);

      await service.saveCredentials('test@gmail.com', 'abcd efgh ijkl mnop');
      expect(await service.isConfigured(), isTrue);
      expect(await service.getSavedEmail(), 'test@gmail.com');
      expect(await service.getSavedAppPassword(), 'abcdefghijklmnop'); // whitespace removed

      await service.dismissEmail('msg_123');
      final dismissed = await service.getDismissedIds();
      expect(dismissed, contains('msg_123'));

      await service.clearCredentials();
      expect(await service.isConfigured(), isFalse);
    });

    test('fetchEmails with fake adapter handles data and dismissed items', () async {
      final service = EmailService.instance;
      final fake = FakeEmailAdapter();
      service.setAdapterForTesting(fake);

      await service.saveCredentials('user@gmail.com', 'testpass12345678');
      await service.dismissEmail('msg_2');

      fake.cannedEmails = <EmailMessageItem>[
        EmailMessageItem(
          id: 'msg_1',
          subject: 'HDFC Bank Alert: Spent INR 500',
          from: 'alerts@hdfcbank.net',
          date: DateTime.now(),
          body: 'Thank you for using your HDFC Bank Credit Card ending in 1234 for INR 500.00 at SWIGGY on 22-09-2026.',
          parsed: EmailParser.parse(
            'Thank you for using your HDFC Bank Credit Card ending in 1234 for INR 500.00 at SWIGGY on 22-09-2026.',
          ),
        ),
        EmailMessageItem(
          id: 'msg_2',
          subject: 'OTP Alert',
          from: 'alerts@hdfcbank.net',
          date: DateTime.now(),
          body: 'Your OTP is 123456',
        ),
      ];

      final items = await service.fetchEmails(days: 14);
      expect(items.length, 2);
      expect(items[0].isDismissed, isFalse);
      expect(items[1].isDismissed, isTrue);
    });
  });

  group('EmailTransactionsScreen widget tests', () {
    final categories = <ExpenseCategory>[
      const ExpenseCategory(id: 1, name: 'Food', icon: '🍔', color: 0xFFFFAA00),
      const ExpenseCategory(id: 2, name: 'Shopping', icon: '🛍️', color: 0xFF00AAFF),
    ];
    final merchants = <String>['SWIGGY', 'AMAZON', 'FLIPKART'];
    final paymentTypes = <String>['HDFC Bank Card 1234', 'Cash', 'UPI'];

    testWidgets('renders initial unconfigured state and opens Paste Email dialog',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = EmailService.instance;
      service.setAdapterForTesting(FakeEmailAdapter());
      await service.clearCredentials();

      await tester.pumpWidget(
        MaterialApp(
          home: EmailTransactionsScreen(
            categories: categories,
            merchants: merchants,
            paymentTypes: paymentTypes,
            transactions: const <ExpenseTxn>[],
            onChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Email Transactions'), findsOneWidget);
      expect(find.text('Paste Email Text'), findsOneWidget);
      expect(find.text('Gmail Not Connected'), findsOneWidget);
      expect(find.text('Connect your Gmail or Paste Email Text'), findsOneWidget);

      // Tap Paste Email Text
      await tester.tap(find.text('Paste Email Text'));
      await tester.pumpAndSettle();

      expect(find.text('Paste Email Alert'), findsOneWidget);
      expect(find.text('Parse & Verify'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Paste Email Alert'), findsNothing);
    });

    testWidgets('Connect Gmail dialog validates inputs and saves credentials',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fake = FakeEmailAdapter();
      final service = EmailService.instance;
      service.setAdapterForTesting(fake);
      await service.clearCredentials();

      await tester.pumpWidget(
        MaterialApp(
          home: EmailTransactionsScreen(
            categories: categories,
            merchants: merchants,
            paymentTypes: paymentTypes,
            transactions: const <ExpenseTxn>[],
            onChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Connect button
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Connect Gmail'), findsOneWidget);

      // Tap Connect without entering text -> shows error
      final dialogConnectBtn = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Connect'),
      );
      await tester.tap(dialogConnectBtn);
      await tester.pumpAndSettle();
      expect(find.text('Please enter both email and App Password.'), findsOneWidget);

      // Fill in valid credentials
      await tester.enterText(
        find.widgetWithText(TextField, 'Gmail Address'),
        'user@gmail.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'App Password'),
        'abcd efgh ijkl mnop',
      );
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(dialogConnectBtn);
      await tester.pumpAndSettle();

      expect(find.text('Connect Gmail'), findsNothing);
      expect(find.text('Connected: user@gmail.com'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('renders fetched emails, smart Added badges, and filters via search bar',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fake = FakeEmailAdapter();
      final service = EmailService.instance;
      service.setAdapterForTesting(fake);
      await service.saveCredentials('user@gmail.com', 'abcd1234efgh5678');

      final today = DateTime.now();
      fake.cannedEmails = <EmailMessageItem>[
        EmailMessageItem(
          id: 'email_1',
          subject: 'HDFC Alert: Spent at SWIGGY',
          from: 'alerts@hdfcbank.net',
          date: today,
          body: 'Thank you for using your HDFC Bank Credit Card ending in 1234 for INR 500.00 at SWIGGY on ${today.day}-${today.month}-${today.year}.',
          parsed: EmailParser.parse(
            'Thank you for using your HDFC Bank Credit Card ending in 1234 for INR 500.00 at SWIGGY on ${today.day}-${today.month}-${today.year}.',
          ),
        ),
        EmailMessageItem(
          id: 'email_2',
          subject: 'SBI Card: Purchase at AMAZON',
          from: 'alerts@sbicard.com',
          date: today,
          body: 'Your SBI Card ending 4321 was used for Rs. 1,299.00 on ${today.day}/${today.month}/${today.year} at AMAZON.',
          parsed: EmailParser.parse(
            'Your SBI Card ending 4321 was used for Rs. 1,299.00 on ${today.day}/${today.month}/${today.year} at AMAZON.',
          ),
        ),
      ];

      // Provide an existing transaction matching email_1 so it gets an 'Added' badge
      final existingTxns = <ExpenseTxn>[
        ExpenseTxn(
          id: 1,
          amount: 500.00,
          merchant: 'SWIGGY',
          paymentType: 'HDFC Bank Card 1234',
          date: today,
          categoryId: 1,
          categoryName: 'Food',
          direction: TxnDirection.debit,
          reference: '',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: EmailTransactionsScreen(
            categories: categories,
            merchants: merchants,
            paymentTypes: paymentTypes,
            transactions: existingTxns,
            onChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HDFC Alert: Spent at SWIGGY'), findsOneWidget);
      expect(find.text('SBI Card: Purchase at AMAZON'), findsOneWidget);

      // Verify Added badge exists on email_1
      expect(find.text('Added'), findsOneWidget);

      // Test Search bar filter
      final searchField = find.widgetWithText(TextField, 'Search subjects, merchants, or senders...');
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'AMAZON');
      await tester.pumpAndSettle();

      expect(find.text('SBI Card: Purchase at AMAZON'), findsOneWidget);
      expect(find.text('HDFC Alert: Spent at SWIGGY'), findsNothing);

      // Clear search
      await tester.enterText(searchField, '');
      await tester.pumpAndSettle();

      expect(find.text('HDFC Alert: Spent at SWIGGY'), findsOneWidget);
      expect(find.text('SBI Card: Purchase at AMAZON'), findsOneWidget);

      // Dismiss second email
      final dismissButtons = find.byTooltip('Dismiss email');
      expect(dismissButtons, findsNWidgets(2));
      await tester.tap(dismissButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('SBI Card: Purchase at AMAZON'), findsNothing);
      expect(find.text('HDFC Alert: Spent at SWIGGY'), findsOneWidget);
    });

    testWidgets('tapping an email opens AddTransactionScreen with pre-filled fields',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final fake = FakeEmailAdapter();
      final service = EmailService.instance;
      service.setAdapterForTesting(fake);
      await service.saveCredentials('user@gmail.com', 'pass123456789012');

      final today = DateTime.now();
      fake.cannedEmails = <EmailMessageItem>[
        EmailMessageItem(
          id: 'email_test',
          subject: 'HDFC Alert',
          from: 'alerts@hdfcbank.net',
          date: today,
          body: 'Thank you for using your HDFC Bank Credit Card ending in 1234 for INR 750.00 at SWIGGY on ${today.day}-${today.month}-${today.year}.',
          parsed: EmailParser.parse(
            'Thank you for using your HDFC Bank Credit Card ending in 1234 for INR 750.00 at SWIGGY on ${today.day}-${today.month}-${today.year}.',
          ),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: EmailTransactionsScreen(
            categories: categories,
            merchants: merchants,
            paymentTypes: paymentTypes,
            transactions: const <ExpenseTxn>[],
            onChanged: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('HDFC Alert'), findsOneWidget);

      // Tap the card
      await tester.tap(find.text('HDFC Alert'));
      await tester.pumpAndSettle();

      // Verify AddTransactionScreen is pushed with prefilled values
      expect(find.byType(AddTransactionScreen), findsOneWidget);
      expect(find.text('750.00'), findsOneWidget);
      expect(find.text('SWIGGY'), findsOneWidget);
      expect(find.text('HDFC Bank Card 1234'), findsOneWidget);
    });
  });
}
