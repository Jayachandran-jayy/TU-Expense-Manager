import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/ledger.dart';
import 'package:tu_expense_tracker/src/core/models.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';
import 'package:tu_expense_tracker/src/core/splits.dart';

void main() {
  group('Budget Calculations & Lookback Windows', () {
    test('budgetLookbackMonths generates previous 2 months plus current month', () {
      final current = YearMonth(2026, 11);
      final lookback = budgetLookbackMonths(current);
      expect(lookback, <YearMonth>[
        YearMonth(2026, 9),
        YearMonth(2026, 10),
        YearMonth(2026, 11),
      ]);
    });

    test('budgetLookbackMonths handles year rollover correctly', () {
      final current = YearMonth(2026, 1);
      final lookback = budgetLookbackMonths(current);
      expect(lookback, <YearMonth>[
        YearMonth(2025, 11),
        YearMonth(2025, 12),
        YearMonth(2026, 1),
      ]);
    });
  });

  group('ExpenseCategory budget serialization', () {
    test('serializes and deserializes budget correctly', () {
      const cat = ExpenseCategory(
        id: 10,
        name: 'Dining',
        icon: '🍔',
        color: 2,
        budget: 5000.0,
      );

      final map = cat.toMap();
      expect(map['budget'], 5000.0);

      final restored = ExpenseCategory.fromMap(map);
      expect(restored.id, 10);
      expect(restored.name, 'Dining');
      expect(restored.icon, '🍔');
      expect(restored.budget, 5000.0);
      expect(restored, cat);
      expect(restored.hashCode, cat.hashCode);
    });

    test('copyWith updates budget or clears it', () {
      const cat = ExpenseCategory(id: 1, name: 'Food', budget: 3000.0);
      final updated = cat.copyWith(budget: 4500.0);
      expect(updated.budget, 4500.0);

      final cleared = updated.copyWith(budget: null);
      expect(cleared.budget, isNull);
    });
  });

  group('deriveBudgetReport', () {
    final targetMonth = YearMonth(2026, 11);

    final categories = <ExpenseCategory>[
      const ExpenseCategory(id: 1, name: 'Uncategorized'),
      const ExpenseCategory(id: 2, name: 'Groceries', budget: 8000.0),
      const ExpenseCategory(id: 3, name: 'Food', budget: 3000.0),
      const ExpenseCategory(id: 4, name: 'Shopping'), // Unbudgeted
    ];

    test('calculates active budgets, over-budget states, and 3-month averages', () {
      final txns = <ExpenseTxn>[
        // Month 9 (Sep 2026)
        ExpenseTxn(
          id: 1,
          amount: 6000.0,
          date: DateTime(2026, 9, 10),
          merchant: 'Supermarket',
          paymentType: 'UPI',
          direction: TxnDirection.debit,
          reference: '',
          categoryId: 2,
          categoryName: 'Groceries',
        ),
        // Month 10 (Oct 2026)
        ExpenseTxn(
          id: 2,
          amount: 7000.0,
          date: DateTime(2026, 10, 15),
          merchant: 'Supermarket',
          paymentType: 'UPI',
          direction: TxnDirection.debit,
          reference: '',
          categoryId: 2,
          categoryName: 'Groceries',
        ),
        // Month 11 (Nov 2026) - Groceries: 5000 (Safe)
        ExpenseTxn(
          id: 3,
          amount: 5000.0,
          date: DateTime(2026, 11, 5),
          merchant: 'Supermarket',
          paymentType: 'UPI',
          direction: TxnDirection.debit,
          reference: '',
          categoryId: 2,
          categoryName: 'Groceries',
        ),
        // Month 11 (Nov 2026) - Food: 3600 (Over budget by 600)
        ExpenseTxn(
          id: 4,
          amount: 3600.0,
          date: DateTime(2026, 11, 8),
          merchant: 'Restaurant',
          paymentType: 'Card',
          direction: TxnDirection.debit,
          reference: '',
          categoryId: 3,
          categoryName: 'Food',
        ),
        // Month 11 (Nov 2026) - Shopping: 1200 (Unbudgeted)
        ExpenseTxn(
          id: 5,
          amount: 1200.0,
          date: DateTime(2026, 11, 12),
          merchant: 'Amazon',
          paymentType: 'Card',
          direction: TxnDirection.debit,
          reference: '',
          categoryId: 4,
          categoryName: 'Shopping',
        ),
        // Credit transaction (Refund) - Must be excluded
        ExpenseTxn(
          id: 6,
          amount: 1000.0,
          date: DateTime(2026, 11, 15),
          merchant: 'Refund',
          paymentType: 'UPI',
          direction: TxnDirection.credit,
          reference: '',
          categoryId: 2,
          categoryName: 'Groceries',
        ),
      ];

      final report = deriveBudgetReport(
        transactions: txns,
        categories: categories,
        targetMonth: targetMonth,
      );

      // Verify active budgets
      expect(report.activeBudgets.length, 2);
      expect(report.unbudgeted.length, 2); // Uncategorized, Shopping

      // Food should be sorted first because it is over budget
      final food = report.activeBudgets.firstWhere((b) => b.category.id == 3);
      expect(food.isOverBudget, isTrue);
      expect(food.budget, 3000.0);
      expect(food.currentSpent, 3600.0);
      expect(food.remaining, -600.0);
      expect(food.progress, 1.0); // Clamped
      expect(food.rawRatio, 1.2);

      // Groceries
      final groceries = report.activeBudgets.firstWhere((b) => b.category.id == 2);
      expect(groceries.isOverBudget, isFalse);
      expect(groceries.budget, 8000.0);
      expect(groceries.currentSpent, 5000.0);
      expect(groceries.remaining, 3000.0);
      expect(groceries.progress, closeTo(5000 / 8000, 0.001));
      expect(groceries.monthSpends[YearMonth(2026, 9)], 6000.0);
      expect(groceries.monthSpends[YearMonth(2026, 10)], 7000.0);
      expect(groceries.monthSpends[YearMonth(2026, 11)], 5000.0);
      // Average: (6000 + 7000 + 5000) / 3 = 6000
      expect(groceries.averageSpend, 6000.0);

      // Overall Summary
      expect(report.overall.totalBudget, 11000.0); // 8000 + 3000
      expect(report.overall.totalSpent, 8600.0); // 5000 + 3600
      expect(report.overall.totalRemaining, 2400.0);
      expect(report.overall.isOverBudget, isFalse);
      expect(report.overall.budgetedCategoryCount, 2);
      expect(report.overall.unbudgetedCategoryCount, 2);
    });

    test('attributes split transactions accurately to each category line', () {
      final splitTxn = ExpenseTxn(
        id: 10,
        amount: 2500.0,
        date: DateTime(2026, 11, 20),
        merchant: 'Hypermarket',
        paymentType: 'UPI',
        direction: TxnDirection.debit,
        reference: '',
        categoryId: 2,
        categoryName: 'Groceries',
        splits: const <TxnSplit>[
          TxnSplit(categoryId: 2, categoryName: 'Groceries', amount: 1500.0),
          TxnSplit(categoryId: 3, categoryName: 'Food', amount: 1000.0),
        ],
      );

      final report = deriveBudgetReport(
        transactions: <ExpenseTxn>[splitTxn],
        categories: categories,
        targetMonth: targetMonth,
      );

      final groc = report.activeBudgets.firstWhere((b) => b.category.id == 2);
      final food = report.activeBudgets.firstWhere((b) => b.category.id == 3);

      expect(groc.currentSpent, 1500.0);
      expect(food.currentSpent, 1000.0);
    });
  });
}
