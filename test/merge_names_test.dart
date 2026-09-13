import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/aliases.dart';
import 'package:tu_expense_tracker/src/core/models.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';
import 'package:tu_expense_tracker/src/mobile/database.dart';
import 'package:tu_expense_tracker/src/mobile/screens/merge_names_screen.dart';

class FakeMergeDatabase implements AppDatabase {
  FakeMergeDatabase({
    List<ExpenseTxn>? transactions,
    NameAliases? aliases,
    List<String>? paymentMethods,
  })  : _txns = transactions ?? <ExpenseTxn>[],
        _aliases = aliases ?? NameAliases.empty,
        _paymentMethods = paymentMethods ?? <String>[];

  final List<ExpenseTxn> _txns;
  NameAliases _aliases;
  final List<String> _paymentMethods;

  @override
  Future<List<ExpenseTxn>> transactions() async => List<ExpenseTxn>.from(_txns);

  @override
  Future<NameAliases> aliases() async => _aliases;

  @override
  Future<List<String>> paymentMethods() async =>
      List<String>.from(_paymentMethods);

  @override
  Future<void> setAliases(NameKind kind, Map<String, String> rows) async {
    final map = <NameKind, Map<String, String>>{
      NameKind.merchant: _aliases.rowsFor(NameKind.merchant),
      NameKind.card: _aliases.rowsFor(NameKind.card),
    };
    map[kind] = Map<String, String>.from(rows);
    _aliases = NameAliases(map);
  }

  @override
  Future<void> addPaymentMethod(String name) async {
    if (!_paymentMethods.contains(name)) {
      _paymentMethods.add(name);
    }
  }

  // --- Unused AppDatabase stubs ---
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  void setLargeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  group('MergeNamesScreen card duplicate filtering', () {
    testWidgets('already-merged cards do not show as duplicates to merge',
        (WidgetTester tester) async {
      setLargeViewport(tester);

      // Simulates the exact state from the user report:
      // 822 transactions canonicalised under 'HDFC Bank CREDIT Card xx6824'
      final txns = List<ExpenseTxn>.generate(
        822,
        (i) => ExpenseTxn(
          id: i + 1,
          amount: 100.0,
          paymentType: 'HDFC Bank CREDIT Card xx6824',
          rawPaymentType:
              i % 2 == 0 ? 'CREDIT Card xx6824' : 'HDFC Bank Card 6824',
          merchant: 'Swiggy',
          rawMerchant: 'Swiggy',
          direction: TxnDirection.debit,
          reference: '',
          date: DateTime(2026, 9, 1),
          categoryId: 2,
          categoryName: 'Food',
        ),
      );

      final aliases = NameAliases.fromRows(<Map<String, Object?>>[
        {
          'kind': 'payment_type',
          'alias': 'credit card xx6824',
          'canonical': 'HDFC Bank CREDIT Card xx6824',
        },
        {
          'kind': 'payment_type',
          'alias': 'hdfc bank card 6824',
          'canonical': 'HDFC Bank CREDIT Card xx6824',
        },
        {
          'kind': 'payment_type',
          'alias': 'hdfc bank card x6824',
          'canonical': 'HDFC Bank CREDIT Card xx6824',
        },
      ]);

      final paymentMethods = <String>[
        'CREDIT Card xx6824',
        'HDFC Bank CREDIT Card xx6824',
        'HDFC Bank Card 6824',
        'HDFC Bank Card x6824',
      ];

      final fakeDb = FakeMergeDatabase(
        transactions: txns,
        aliases: aliases,
        paymentMethods: paymentMethods,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MergeNamesScreen(
            kind: NameKind.card,
            database: fakeDb,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Looks like duplicates" must NOT be shown for these cards
      expect(find.text('Merge these 4'), findsNothing);
      expect(find.text('Looks like duplicates'), findsNothing);

      // "Merged" section must show the canonical card with Separate action
      expect(find.text('Merged'), findsOneWidget);
      expect(find.text('HDFC Bank CREDIT Card xx6824'), findsNWidgets(2)); // Merged tile + All list
      expect(find.text('Separate'), findsOneWidget);

      // Under "All cards & accounts", only the canonical card is shown with count 822
      expect(find.text('822 transactions'), findsOneWidget);
      // Merged aliases should not be shown as separate unmerged 0-count tiles
      expect(find.text('CREDIT Card xx6824'), findsNothing);
      expect(find.text('HDFC Bank Card 6824'), findsNothing);
    });

    testWidgets(
        'unmerged cards sharing trailing digits show suggestion and card is clickable',
        (WidgetTester tester) async {
      setLargeViewport(tester);

      final paymentMethods = <String>[
        'HDFC Bank Card 6824',
        'SBI Card 6824',
      ];

      final fakeDb = FakeMergeDatabase(
        transactions: <ExpenseTxn>[],
        aliases: NameAliases.empty,
        paymentMethods: paymentMethods,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MergeNamesScreen(
            kind: NameKind.card,
            database: fakeDb,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // "Looks like duplicates" section is displayed
      expect(find.text('Looks like duplicates'), findsOneWidget);
      expect(find.text('Merge these 2'), findsOneWidget);

      // Tapping the card opens the merge bottom sheet
      await tester.tap(find.text('Merge these 2'));
      await tester.pumpAndSettle();

      expect(find.text('Merge 2 cards & accounts'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Merge'), findsOneWidget);

      // Submit merge
      await tester.tap(find.widgetWithText(FilledButton, 'Merge'));
      await tester.pumpAndSettle();

      // Suggestion must now be gone since they are merged
      expect(find.text('Merge these 2'), findsNothing);
      expect(find.text('Looks like duplicates'), findsNothing);

      // Must be shown in Merged section
      expect(find.text('Merged'), findsOneWidget);
      expect(find.text('Separate'), findsOneWidget);

      // Tap Separate to unmerge
      await tester.tap(find.text('Separate'));
      await tester.pumpAndSettle();

      // Suggestion must reappear
      expect(find.text('Looks like duplicates'), findsOneWidget);
      expect(find.text('Merge these 2'), findsOneWidget);
    });
  });
}
