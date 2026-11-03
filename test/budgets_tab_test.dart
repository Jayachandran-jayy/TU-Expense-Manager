import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/ledger.dart';
import 'package:tu_expense_tracker/src/core/models.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';
import 'package:tu_expense_tracker/src/ui_shared/budgets_tab.dart';
import 'package:tu_expense_tracker/src/ui_shared/formats.dart';

void main() {
  final money = appMoneyFormat();
  final currentMonth = YearMonth(2026, 11);

  final categories = <ExpenseCategory>[
    const ExpenseCategory(id: 1, name: 'Uncategorized'),
    const ExpenseCategory(id: 2, name: 'Groceries', icon: '🛒', color: 1, budget: 6000.0),
    const ExpenseCategory(id: 3, name: 'Food', icon: '🍔', color: 2, budget: 2000.0),
    const ExpenseCategory(id: 4, name: 'Shopping', icon: '🛍️', color: 3), // Unbudgeted
  ];

  final txns = <ExpenseTxn>[
    ExpenseTxn(
      id: 1,
      amount: 4500.0,
      date: DateTime(2026, 11, 4),
      merchant: 'Supermarket',
      paymentType: 'UPI',
      direction: TxnDirection.debit,
      reference: 'REF1',
      categoryId: 2,
      categoryName: 'Groceries',
      categoryIcon: '🛒',
    ),
    ExpenseTxn(
      id: 2,
      amount: 2500.0, // Over budget by 500
      date: DateTime(2026, 11, 6),
      merchant: 'Burger Place',
      paymentType: 'Card',
      direction: TxnDirection.debit,
      reference: 'REF2',
      categoryId: 3,
      categoryName: 'Food',
      categoryIcon: '🍔',
    ),
    ExpenseTxn(
      id: 3,
      amount: 1500.0,
      date: DateTime(2026, 11, 10),
      merchant: 'Mall',
      paymentType: 'Card',
      direction: TxnDirection.debit,
      reference: 'REF3',
      categoryId: 4,
      categoryName: 'Shopping',
      categoryIcon: '🛍️',
    ),
  ];

  Widget buildTestWidget({
    YearMonth? targetMonth,
    ValueChanged<YearMonth>? onMonthChanged,
    Future<void> Function(ExpenseCategory, double?)? onSetBudget,
    void Function(ExpenseCategory, YearMonth)? onViewCategoryTransactions,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: BudgetsTab(
          transactions: txns,
          categories: categories,
          targetMonth: targetMonth ?? currentMonth,
          currentMonth: currentMonth,
          money: money,
          loading: false,
          onMonthChanged: onMonthChanged ?? (_) {},
          onRefresh: () async {},
          onSetBudget: onSetBudget ?? (_, _) async {},
          onViewCategoryTransactions: onViewCategoryTransactions,
        ),
      ),
    );
  }

  group('BudgetsTab Widget Tests', () {
    testWidgets('renders month navigator, overall card, active budgets and unbudgeted list', (tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Month navigator shows November 2026
      expect(find.text('Nov 2026'), findsOneWidget);

      // Overall budget card: Total Budget is 6000 + 2000 = 8000
      expect(find.textContaining('Overall Budget'), findsOneWidget);
      expect(find.text(money.format(8000.0)), findsOneWidget);

      // Active budgets section
      expect(find.textContaining('Active Budgets (2)'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);

      // Over budget badge on Food
      expect(find.textContaining('over'), findsOneWidget);

      // Unbudgeted categories section
      expect(find.textContaining('Unbudgeted Categories'), findsOneWidget);
      expect(find.text('Shopping'), findsOneWidget);
      expect(find.text('Set budget'), findsWidgets);
    });

    testWidgets('month navigator chevrons trigger onMonthChanged', (tester) async {
      YearMonth? changedMonth;
      await tester.pumpWidget(buildTestWidget(
        onMonthChanged: (m) => changedMonth = m,
      ));
      await tester.pumpAndSettle();

      // Tap previous month
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pumpAndSettle();
      expect(changedMonth, YearMonth(2026, 10));

      // Tap next month
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(changedMonth, YearMonth(2026, 12));
    });

    testWidgets('tapping active budget card opens editor and saves updated budget', (tester) async {
      ExpenseCategory? savedCat;
      double? savedAmount;

      await tester.pumpWidget(buildTestWidget(
        onSetBudget: (cat, b) async {
          savedCat = cat;
          savedAmount = b;
        },
      ));
      await tester.pumpAndSettle();

      // Tap Groceries card
      await tester.tap(find.text('Groceries'));
      await tester.pumpAndSettle();

      // Bottom sheet header
      expect(find.text('Edit Category Budget'), findsOneWidget);

      // Enter new amount
      final field = find.byType(TextField);
      expect(field, findsOneWidget);
      await tester.enterText(field, '7500');

      // Tap Save Budget
      await tester.tap(find.text('Save Budget'));
      await tester.pumpAndSettle();

      expect(savedCat?.name, 'Groceries');
      expect(savedAmount, 7500.0);
    });

    testWidgets('tapping Remove Budget Target clears budget', (tester) async {
      ExpenseCategory? savedCat;
      double? savedAmount;

      await tester.pumpWidget(buildTestWidget(
        onSetBudget: (cat, b) async {
          savedCat = cat;
          savedAmount = b;
        },
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();

      // Tap Remove Budget Target
      await tester.tap(find.text('Remove Budget Target'));
      await tester.pumpAndSettle();

      expect(savedCat?.name, 'Food');
      expect(savedAmount, isNull);
    });

    testWidgets('tapping view transactions shortcut invokes callback', (tester) async {
      ExpenseCategory? selectedCat;
      YearMonth? selectedMonth;

      await tester.pumpWidget(buildTestWidget(
        onViewCategoryTransactions: (cat, m) {
          selectedCat = cat;
          selectedMonth = m;
        },
      ));
      await tester.pumpAndSettle();

      final shortcut = find.byTooltip('View transactions').first;
      await tester.tap(shortcut);
      await tester.pumpAndSettle();

      expect(selectedCat, isNotNull);
      expect(selectedMonth, currentMonth);
    });
  });
}
