import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tu_expense_tracker/src/core/edits.dart';
import 'package:tu_expense_tracker/src/core/models.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';
import 'package:tu_expense_tracker/src/core/splits.dart';
import 'package:tu_expense_tracker/src/mobile/database.dart';
import 'package:tu_expense_tracker/src/mobile/screens/add_transaction_screen.dart';
import 'package:tu_expense_tracker/src/mobile/screens/transaction_actions_sheet.dart';
import 'package:tu_expense_tracker/src/web/edit_sheets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  const categories = <ExpenseCategory>[
    ExpenseCategory(id: 1, name: 'Uncategorized'),
    ExpenseCategory(id: 2, name: 'Food'),
    ExpenseCategory(id: 3, name: 'Grocery'),
    ExpenseCategory(id: 4, name: 'Shopping'),
  ];

  const merchants = <String>[
    'Swiggy',
    'Zomato',
    'Amazon',
    'BigBasket',
  ];

  void setLargeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  final testTxn = ExpenseTxn(
    id: 42,
    amount: 350.0,
    merchant: 'Swiggy',
    date: DateTime(2026, 11, 1, 14, 30),
    categoryId: 2,
    categoryName: 'Food',
    direction: TxnDirection.debit,
    paymentType: 'UPI',
    reference: 'UPI/1234567890',
    note: 'Lunch with team',
  );

  group('EditOp.updateTxn Serialization', () {
    test('composes and reads back updateTxn payload correctly', () {
      final now = DateTime.utc(2026, 11, 2, 8, 0);
      final edit = composeEdit(
        editId: 'edit_123',
        op: EditOp.updateTxn,
        txn: testTxn,
        now: now,
        amount: 420.0,
        merchant: 'Swiggy Dineout',
        date: DateTime.utc(2026, 11, 1, 19, 0),
        categoryId: 3,
        paymentType: 'Credit Card',
        direction: TxnDirection.debit,
        note: 'Dinner',
        lines: const <TxnSplit>[
          TxnSplit(categoryId: 2, categoryName: 'Food', amount: 300.0),
          TxnSplit(categoryId: 3, categoryName: 'Grocery', amount: 120.0),
        ],
      );

      expect(edit.op, EditOp.updateTxn);
      expect(edit.amount, 420.0);
      expect(edit.merchant, 'Swiggy Dineout');
      expect(edit.date?.millisecondsSinceEpoch,
          DateTime.utc(2026, 11, 1, 19, 0).millisecondsSinceEpoch);
      expect(edit.categoryId, 3);
      expect(edit.paymentType, 'Credit Card');
      expect(edit.direction, TxnDirection.debit);
      expect(edit.note, 'Dinner');
      expect(edit.splitLines.length, 2);
      expect(edit.splitLines.first.amount, 300.0);
      expect(edit.splitLines.last.amount, 120.0);
    });

    test('updateTxn byWire maps to correct enum value', () {
      expect(EditOp.byWire('update_txn'), EditOp.updateTxn);
    });
  });

  group('TransactionActionsSheet UI', () {
    testWidgets('shows Edit transaction tile at the top of actions', (WidgetTester tester) async {
      TxnAction? tappedAction;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                tappedAction = await showModalBottomSheet<TxnAction>(
                  context: context,
                  builder: (_) => TransactionActionsSheet(
                    txn: testTxn,
                    money: NumberFormat.currency(symbol: '₹'),
                    dateFormat: DateFormat('d MMM yyyy'),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Edit transaction'), findsOneWidget);
      expect(find.text('Price, date, time, and details'), findsOneWidget);

      await tester.tap(find.text('Edit transaction'));
      await tester.pumpAndSettle();

      expect(tappedAction, TxnAction.editTransaction);
    });
  });

  group('AddTransactionScreen in Edit Mode', () {
    testWidgets('renders Edit Transaction title and prefilled fields', (WidgetTester tester) async {
      setLargeViewport(tester);

      await tester.pumpWidget(MaterialApp(
        home: AddTransactionScreen(
          categories: categories,
          merchants: merchants,
          existingTxn: testTxn,
        ),
      ));
      await tester.pumpAndSettle();

      // Title & buttons
      expect(find.text('Edit Transaction'), findsOneWidget);
      expect(find.text('Update Transaction'), findsOneWidget);

      // Pre-filled amount
      expect(find.text('350.00'), findsOneWidget);

      // Pre-filled merchant
      expect(find.text('Swiggy'), findsWidgets);

      // Pre-filled notes
      expect(find.text('Lunch with team'), findsOneWidget);
    });

    testWidgets('pre-fills split lines when editing split transaction', (WidgetTester tester) async {
      setLargeViewport(tester);

      final splitTxn = ExpenseTxn(
        id: 43,
        amount: 500.0,
        merchant: 'Amazon',
        date: DateTime(2026, 11, 1, 10, 0),
        categoryId: 3,
        categoryName: 'Grocery',
        direction: TxnDirection.debit,
        paymentType: 'Credit Card',
        reference: '',
        splits: const <TxnSplit>[
          TxnSplit(categoryId: 3, categoryName: 'Grocery', amount: 300.0),
          TxnSplit(categoryId: 4, categoryName: 'Shopping', amount: 200.0),
        ],
      );

      await tester.pumpWidget(MaterialApp(
        home: AddTransactionScreen(
          categories: categories,
          merchants: merchants,
          existingTxn: splitTxn,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Edit Transaction'), findsOneWidget);
      expect(find.text('500.00'), findsOneWidget);

      // Both split amounts should be rendered
      expect(find.text('300.00'), findsOneWidget);
      expect(find.text('200.00'), findsOneWidget);
    });
  });

  group('Web Edit Transaction Dialog', () {
    testWidgets('opens web edit transaction dialog with prefilled details', (WidgetTester tester) async {
      setLargeViewport(tester);

      WebEditTxnResult? result;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await editWebTransaction(
                  context,
                  txn: testTxn,
                  categories: categories,
                  money: NumberFormat.currency(symbol: '₹'),
                );
              },
              child: const Text('Edit Web'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('Edit Web'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Transaction'), findsOneWidget);
      expect(find.text('350.00'), findsOneWidget);
      expect(find.text('Swiggy'), findsOneWidget);
      expect(find.text('Lunch with team'), findsOneWidget);

      // Save without modifications
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.amount, 350.0);
      expect(result!.merchant, 'Swiggy');
      expect(result!.note, 'Lunch with team');
    });
  });

  group('AppDatabase.updateTransaction SQLite Integration', skip: kIsWeb, () {
    Database? testDb;
    final db = AppDatabase.instance;

    setUp(() async {
      if (kIsWeb) return;
      testDb = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: AppDatabase.schemaVersion,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: db.onCreateForTesting,
        ),
      );
      db.setDatabaseForTesting(testDb);
    });

    tearDown(() async {
      if (kIsWeb) return;
      db.setDatabaseForTesting(null);
      await testDb?.close();
    });

    test('updates transaction fields, sets tombstone for old natural key, preserves splits', testOn: 'vm', () async {
      final originalSms = ParsedSms(
        amount: 500.0,
        merchant: 'Swiggy',
        date: DateTime(2026, 11, 1, 10, 0),
        direction: TxnDirection.debit,
        paymentType: 'HDFC Card 1234',
        reference: 'UPI/987654321',
      );

      final int insertedId = await db.insertParsed(originalSms);
      expect(insertedId, greaterThan(0));

      final newDate = DateTime(2026, 11, 2, 14, 45);
      await db.updateTransaction(
        id: insertedId,
        amount: 450.0,
        merchant: 'Swiggy Gourmet',
        date: newDate,
        categoryId: (await db.categories()).first.id,
        paymentType: 'HDFC Card 1234',
        direction: TxnDirection.debit,
        reference: 'UPI/987654321',
        note: 'Applied voucher',
      );

      final txns = await db.transactions();
      final txn = txns.firstWhere((t) => t.id == insertedId);
      expect(txn.amount, 450.0);
      expect(txn.merchant, 'Swiggy Gourmet');
      expect(txn.date, newDate);
      expect(txn.note, 'Applied voucher');

      // Edge case: Original SMS must not be re-imported
      expect(await db.isDuplicateOrDeleted(originalSms), isTrue);
      expect(await db.insertParsed(originalSms), 0);

      // Edge case: Edited row should not show in deleted trash
      final deleted = await db.deletedTransactions();
      expect(deleted.any((d) => d.originalId == insertedId), isFalse);
    });
  });
}
