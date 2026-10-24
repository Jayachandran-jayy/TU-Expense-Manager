import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';
import 'package:tu_expense_tracker/src/core/statement_parser.dart';

// Synthetic statements in the shapes PDFBox extracts. No real customer data.
const String _yesCard = '''
Statement for YES BANK Card Number 1234XXXXXXXX9999
17/09/2026 To 16/10/2026 Rs. 1,00,000.00 Current Purchases / Cash Advance
Date Transaction Details Merchant Category Amount (Rs.)
16/09/2026 UPI_TEST STORE CHENNAI IND - Ref No: RT111 Miscellaneous Stores 1,59,900.00 Dr
UPI_LONG NAME TRADERS IND - Ref No:
18/09/2026 Retail Outlet Services 40.00 Dr
01/10/2026 PAYMENT RECEIVED BBPS - Ref No: 0999 22,779.13 Cr
''';

const String _hdfcCard = '''
HDFC Bank Credit Cards
Credit Card No. 500000XXXXXX1111
22/09/2026| 15:38 Test Pharmacy LtdChennai  C 503.29 l
22/09/2026| 00:00 Test Pharmacy LtdChennai +  C 1.00 l
CC PAYMENT 0000 PayZapp (Ref#
01/10/2026| 08:25 +  C 7,409.00 l
18/10/2026| 00:00 OFFUS EMI,INT (Ref# 0999)  C 63.00 l
''';

const String _hdfcSavings = '''
HDFC BANK LIMITED
Account No : 50100000001234 CLASSIC
09/10/26 UPI-TEST SHOP 0000628200000001 09/10/26 40.00 1,000.00
R-TESTSHOP@OKSBI
10/10/26 NEFT CR-SALARY 0000000000000002 10/10/26 500.00 1,500.00
10/10/26 POS 400000XXXXXX0000 TEST 0000628300000003 10/10/26 300.00 1,200.00
STATEMENT SUMMARY :-
Opening Balance Dr Count Cr Count Debits Credits Closing Bal
1,040.00 2 1 340.00 500.00 1,200.00
''';

// Layouts the reader was not written for, to show it needs no per-bank code.
const String _sbiLike = '''
STATE BANK OF INDIA
Account Number : 00000099990000004321
Date Description Amount
1-7 TEST NAGAR 5TH STREET 1,234.00
01 Oct 2026 OPENING BALANCE 5,000.00
05 Oct 2026 TO TRANSFER-UPI/DR/TESTFOOD 250.00 D
06 Oct 2026 BY TRANSFER-SALARY 1,000.00 C
07-Oct-26 ATM WDL TEST ATM 1,500.00 DR
19 Sep, 2026 - 18 Oct, 2026
''';

const String _iciciLike = '''
ICICI Bank
A/c No : XXXXXXXX5555
Date Particulars Withdrawals Deposits Balance
05-10-2026 UPI/TESTSHOP/123456789012 500.00 12,000.00
06-10-2026 NEFT-REFUND 300.00 12,300.00
''';

void main() {
  group('parseStatement', () {
    test('YES card: Dr rows only, wrapped description, merchant matches the SMS name', () {
      final rows = parseStatement(_yesCard);
      expect(rows.map((r) => r.parsed.amount), <double>[159900.00, 40.00]);
      expect(rows[0].parsed.merchant, 'TEST STORE CHENNAI');
      expect(rows[0].parsed.reference, 'RT111');
      expect(rows[0].parsed.date, DateTime(2026, 9, 16));
      expect(rows[0].parsed.hasExplicitTime, isFalse);
      expect(rows[1].parsed.merchant, 'LONG NAME TRADERS');
      expect(rows[1].parsed.paymentType, 'Card X9999');
    });

    test('HDFC card: + rows are credits, time kept, Ref# stripped', () {
      final rows = parseStatement(_hdfcCard);
      expect(rows.map((r) => r.parsed.amount), <double>[503.29, 63.00]);
      expect(rows[0].parsed.date, DateTime(2026, 9, 22, 15, 38));
      expect(rows[0].parsed.hasExplicitTime, isTrue);
      expect(rows[1].parsed.merchant, 'OFFUS EMI,INT');
      expect(rows[1].parsed.hasExplicitTime, isFalse);
      expect(rows[0].parsed.paymentType, 'Card X1111');
    });

    test('HDFC savings: direction from the balance, account beats the POS card number', () {
      final rows = parseStatement(_hdfcSavings);
      expect(rows.map((r) => r.parsed.amount), <double>[40.00, 300.00]);
      expect(rows[0].parsed.date, DateTime(2026, 10, 9));
      expect(rows[0].parsed.reference, '628200000001');
      expect(rows[0].parsed.paymentType, 'A/c XX1234');
    });

    test('uses the existing name for the same card', () {
      final rows = parseStatement(_hdfcCard,
          knownPaymentTypes: <String>['Cash', 'HDFC Bank Card 1111']);
      expect(rows.first.parsed.paymentType, 'HDFC Bank Card 1111');
    });

    test('another bank: D/C and DR markers, opening balance and non-rows skipped', () {
      final rows = parseStatement(_sbiLike);
      expect(rows.map((r) => r.parsed.amount), <double>[250.00, 1500.00]);
      expect(rows[0].parsed.date, DateTime(2026, 10, 5));
      expect(rows[0].parsed.merchant, 'TO TRANSFER-UPI/DR/TESTFOOD');
      expect(rows[1].parsed.date, DateTime(2026, 10, 7));
      expect(rows[0].parsed.paymentType, 'A/c XX4321');
    });

    test('another savings layout: balance with no opening balance line', () {
      final rows = parseStatement(_iciciLike);
      expect(rows.map((r) => r.parsed.amount), <double>[500.00]);
      expect(rows.single.parsed.reference, '123456789012');
      expect(rows.single.parsed.merchant, 'TESTSHOP');
      expect(rows.single.parsed.paymentType, 'A/c XX5555');
    });
  });

  group('statementExcerpt', () {
    test('header and rows only, with numbers and balances masked', () {
      final excerpt = statementExcerpt('''
TEST PERSON
1-7 TEST NAGAR, CHENNAI 600089
Account No : 50100000001234
$_hdfcSavings''');
      expect(excerpt, isNot(contains('TEST PERSON')));
      expect(excerpt, isNot(contains('TEST NAGAR')));
      expect(excerpt, isNot(matches(RegExp(r'\d{6,}'))));
      expect(excerpt, contains('[BALANCE]'));
      expect(excerpt, contains('[CARD]'));
      expect(excerpt, contains('40.00'));
    });

    test('unknown layout: dotted dates are not taken for amounts', () {
      final excerpt = statementExcerpt('250.00   TEST CAFE   05.10.2026\n1,240.50   TEST MART   06.10.2026');
      expect(excerpt, contains('05.10.2026'));
      expect(excerpt, isNot(contains('[BALANCE]')));
    });

    test('lines for the on-device model need an amount and a date', () {
      expect(
        statementCandidateLines('Card 4321XXXXXXXX9876\n250.00  TEST CAFE  05.10.2026\nTotal due 1,579.50'),
        <String>['250.00  TEST CAFE  05.10.2026'],
      );
    });

    test('keeps the column header when there is one', () {
      expect(statementExcerpt(_iciciLike).split('\n').first,
          'Date Particulars Withdrawals Deposits Balance');
    });

    test('bank hint for the issue title', () {
      expect(statementBankHint(_yesCard), 'YES Bank');
      expect(statementBankHint('nothing here'), '');
      expect(statementBankHint('HDFC BANK LIMITED\nACH D- IDBI BANK LTD\nHDFC Bank House'), 'HDFC Bank');
    });
  });

  group('notYetRecorded', () {
    StatementRow row(double amount, DateTime date, [String card = 'Card X0001']) => (
          parsed: ParsedSms(
            amount: amount,
            paymentType: card,
            merchant: 'SHOP',
            date: date,
            direction: TxnDirection.debit,
          ),
          line: '',
        );
    RecordedSpend spent(double amount, DateTime date, [String card = 'Card X0001']) =>
        (amount: amount, date: date, paymentType: card);

    test('each recorded spend accounts for one row only', () {
      final day = DateTime(2026, 9, 24);
      final missing = notYetRecorded(
        <StatementRow>[row(100, day), row(100, day)],
        <RecordedSpend>[spent(100, day.add(const Duration(hours: 10)))],
      );
      expect(missing, hasLength(1));
    });

    test('a day apart still matches, two days does not', () {
      final missing = notYetRecorded(
        <StatementRow>[row(50, DateTime(2026, 10, 10)), row(60, DateTime(2026, 10, 10))],
        <RecordedSpend>[spent(50, DateTime(2026, 10, 9, 23)), spent(60, DateTime(2026, 10, 12))],
      );
      expect(missing.map((r) => r.parsed.amount), <double>[60]);
    });

    test('same-day match wins over a neighbouring day', () {
      // Row 1 (9th) could take the 10th's entry; row 2 (10th) must keep it.
      final missing = notYetRecorded(
        <StatementRow>[row(20, DateTime(2026, 10, 9)), row(20, DateTime(2026, 10, 10))],
        <RecordedSpend>[spent(20, DateTime(2026, 10, 10))],
      );
      expect(missing.single.parsed.date, DateTime(2026, 10, 9));
    });

    test('another card does not match; a name without digits does', () {
      final day = DateTime(2026, 10, 9);
      final rows = <StatementRow>[row(500, day, 'HDFC Bank A/c XX1234')];
      expect(notYetRecorded(rows, <RecordedSpend>[spent(500, day, 'YES BANK Card X9999')]), hasLength(1));
      expect(notYetRecorded(rows, <RecordedSpend>[spent(500, day, 'HDFC Bank A/C *1234')]), isEmpty);
      expect(notYetRecorded(rows, <RecordedSpend>[spent(500, day, 'Unknown')]), isEmpty);
    });

    test('different amount is not a match', () {
      final missing = notYetRecorded(
        <StatementRow>[row(115.40, DateTime(2026, 10, 9))],
        <RecordedSpend>[spent(115.04, DateTime(2026, 10, 9))],
      );
      expect(missing, hasLength(1));
    });
  });
}
