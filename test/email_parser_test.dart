import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/email_parser.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';

void main() {
  group('EmailParser.stripHtml', () {
    test('strips HTML tags and decodes entities correctly', () {
      const html = '''
        <html>
          <head>
            <style>body { color: red; }</style>
            <script>alert("test");</script>
          </head>
          <body>
            <div>Dear Customer,</div>
            <p>Your card has been debited for &#8377;&nbsp;1,250.00 at <b>AMAZON &amp; CO</b> on 22-09-2026.</p>
          </body>
        </html>
      ''';

      final stripped = EmailParser.stripHtml(html);
      expect(stripped, contains('Dear Customer,'));
      expect(stripped, contains('Your card has been debited for ₹ 1,250.00 at AMAZON & CO on 22-09-2026.'));
      expect(stripped, isNot(contains('style')));
      expect(stripped, isNot(contains('alert')));
      expect(stripped, isNot(contains('<div>')));
    });
  });

  group('EmailParser bank issuers', () {
    test('parses HDFC Bank credit card spend alert', () {
      const email = '''
        Dear Customer,
        Thank you for using your HDFC Bank Credit Card ending in 8174 for INR 1,599.00 at AMAZON INDIA on 22-09-2026 14:30:15.
        Auth code: 987654.
        Available limit: INR 1,50,000.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 1599.00);
      expect(parsed.paymentType, 'HDFC Bank Card 8174');
      expect(parsed.merchant, 'AMAZON INDIA');
      expect(parsed.date.year, 2026);
      expect(parsed.date.month, 9);
      expect(parsed.date.day, 22);
      expect(parsed.date.hour, 14);
      expect(parsed.date.minute, 30);
      expect(parsed.direction, TxnDirection.debit);
      expect(parsed.reference, '987654');
      expect(parsed.bank, 'hdfc');
      expect(parsed.hasExplicitTime, isTrue);

      final smsEquivalent = parsed.toParsedSms();
      expect(smsEquivalent.amount, 1599.00);
      expect(smsEquivalent.merchant, 'AMAZON INDIA');
      expect(smsEquivalent.templateId, 'email_hdfc');
    });

    test('parses HDFC Bank debited alert', () {
      const email = '''
        INR 450.00 has been debited from your HDFC Bank Card ending 9012 towards UPI_SWIGGY on 21-09-2026.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 450.00);
      expect(parsed.paymentType, 'HDFC Bank Card 9012');
      expect(parsed.merchant, 'SWIGGY'); // cleanMerchantName strips UPI_
      expect(parsed.date.day, 21);
      expect(parsed.direction, TxnDirection.debit);
      expect(parsed.hasExplicitTime, isFalse);
    });

    test('parses ICICI Bank credit card alert', () {
      const email = '''
        Dear Customer,
        Your ICICI Bank Credit Card XX1004 has been used for a transaction of INR 2,499.00 on Sep 21, 2026 at 11:20:00. Info: FLIPKART. The Available Credit Limit is INR 85,000.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 2499.00);
      expect(parsed.paymentType, 'ICICI Bank Card 1004');
      expect(parsed.merchant, 'FLIPKART');
      expect(parsed.date.month, 9);
      expect(parsed.date.day, 21);
      expect(parsed.date.hour, 11);
      expect(parsed.date.minute, 20);
      expect(parsed.bank, 'icici');
    });

    test('parses SBI Card transaction alert', () {
      const email = '''
        Dear Cardholder,
        Thank you for using your SBI Credit Card ending in 4321 for Rs. 1,299.50 at MYNTRA on 22/09/2026.
        Ref no. 12345678.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 1299.50);
      expect(parsed.paymentType, 'SBI Card 4321');
      expect(parsed.merchant, 'MYNTRA');
      expect(parsed.date.day, 22);
      expect(parsed.date.month, 9);
      expect(parsed.date.year, 2026);
      expect(parsed.reference, '12345678');
      expect(parsed.bank, 'sbi');
    });

    test('parses Axis Bank transaction alert', () {
      const email = '''
        Your Axis Bank Card no. XX3456 was used for INR 850.00 on 22-09-2026 18:30:00 at STARBUCKS. Available limit INR 65,000.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 850.00);
      expect(parsed.paymentType, 'Axis Bank Card 3456');
      expect(parsed.merchant, 'STARBUCKS');
      expect(parsed.date.hour, 18);
      expect(parsed.date.minute, 30);
      expect(parsed.bank, 'axis');
    });

    test('parses YES Bank spend alert', () {
      const email = '''
        INR 204.00 spent on YES BANK Card X2858 at UPI_GEORGE EGG CENTRE 13-08-2026 09:21:35 am.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 204.00);
      expect(parsed.paymentType, 'YES BANK Card 2858');
      expect(parsed.merchant, 'GEORGE EGG CENTRE');
      expect(parsed.date.month, 8);
      expect(parsed.date.day, 13);
      expect(parsed.date.hour, 9);
      expect(parsed.date.minute, 21);
      expect(parsed.bank, 'yes');
    });

    test('parses Kotak Mahindra Bank alert', () {
      const email = '''
        Rs. 720.00 was spent on your Kotak Credit Card ending 8899 on 21-09-2026 at MCDONALDS. Avl lmt Rs. 40,000.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 720.00);
      expect(parsed.paymentType, 'Kotak Card 8899');
      expect(parsed.merchant, 'MCDONALDS');
      expect(parsed.bank, 'kotak');
    });

    test('parses IndusInd Bank alert', () {
      const email = '''
        Thank you for using your IndusInd Bank Credit Card ending 6789 for INR 1,890.00 at CAFE COFFEE DAY on 22-09-2026.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 1890.00);
      expect(parsed.paymentType, 'IndusInd Bank Card 6789');
      expect(parsed.merchant, 'CAFE COFFEE DAY');
      expect(parsed.bank, 'indusind');
    });
  });

  group('EmailParser generic fallback & helpers', () {
    test('parses generic email format with refund direction', () {
      const email = '''
        Dear Customer,
        A refund of INR 650.00 has been credited to your Federal Bank Card ending in 4567 from ZOMATO on 22-09-2026.
        Txn ID: REF998877.
      ''';

      final parsed = EmailParser.parse(email);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 650.00);
      expect(parsed.paymentType, contains('4567'));
      expect(parsed.direction, TxnDirection.credit);
      expect(parsed.reference, 'REF998877');
      expect(parsed.bank, 'generic');
    });

    test('extractAmountOnly extracts amount accurately', () {
      expect(EmailParser.extractAmountOnly('Spent INR 3,450.50 at store'), 3450.50);
      expect(EmailParser.extractAmountOnly('Paid Rs. 99.00 for item'), 99.00);
      expect(EmailParser.extractAmountOnly('Charged ₹1500 on card'), 1500.00);
      expect(EmailParser.extractAmountOnly('No money mentioned here'), isNull);
    });

    test('extractInstrumentOnly extracts card instruments', () {
      expect(EmailParser.extractInstrumentOnly('used on HDFC Bank Credit Card ending 1234'), 'HDFC Bank Credit Card 1234');
      expect(EmailParser.extractInstrumentOnly('alert for Card XX5678'), 'Card 5678');
      expect(EmailParser.extractInstrumentOnly('no card here'), isNull);
    });

    test('extractMerchantOnly extracts payee/merchant', () {
      expect(EmailParser.extractMerchantOnly('spent at STARBUCKS on 22-09-2026'), 'STARBUCKS');
      expect(EmailParser.extractMerchantOnly('paid towards SWIGGY. Ref 123'), 'SWIGGY');
    });

    test('extractDateOnly parses diverse date structures', () {
      final d1 = EmailParser.extractDateOnly('on 22-09-2026');
      expect(d1?.date.year, 2026);
      expect(d1?.date.month, 9);
      expect(d1?.date.day, 22);

      final d2 = EmailParser.extractDateOnly('on Sep 21, 2026 at 10:30 am');
      expect(d2?.date.month, 9);
      expect(d2?.date.day, 21);
      expect(d2?.date.hour, 10);
      expect(d2?.date.minute, 30);
      expect(d2?.hasTime, isTrue);
    });
  });
}
