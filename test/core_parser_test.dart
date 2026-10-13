import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';

void main() {
  group('SmsParser', () {
    test('looksLikeTransaction matches HDFC loose templates', () {
      const sms1 = 'Amt Deducted! Rs.11500 from your HDFC Bank A/c XX0444 for NEFT txn via HDFC Bank Online Banking Not you?Call 18002586161/SMS BLOCK OB to 7308080808';
      const sms2 = 'Txn Rs.755.00\nOn HDFC Bank Card 8174\nAt hathwaymobileapp.76062993 \nby UPI 250214536533\nOn 01-09\nNot You?';
      
      expect(SmsParser.looksLikeTransaction(sms1), isTrue);
      expect(SmsParser.looksLikeTransaction(sms2), isTrue);
    });
    
    test('looksLikeTransaction ignores random texts', () {
      expect(SmsParser.looksLikeTransaction('Hey, how are you?'), isFalse);
      expect(SmsParser.looksLikeTransaction('Your OTP is 123456'), isFalse);
    });

    test('extractAmountOnly finds the amount in a message a full parse would reject', () {
      // No recognisable merchant/date shape, so SmsParser.parse returns null —
      // this is exactly what ends up in the unadded-SMS inbox.
      const sms = 'Amt Deducted! Rs.11500 from your HDFC Bank A/c XX0444 for '
          'something the date/merchant patterns do not recognise';
      expect(SmsParser.parse(sms), isNull);
      expect(SmsParser.extractAmountOnly(sms), 11500);
    });

    test('extractAmountOnly handles Indian grouping and decimals', () {
      expect(SmsParser.extractAmountOnly('INR 3,99,614.00 blocked'), 399614.00);
      expect(SmsParser.extractAmountOnly('₹53 spent'), 53);
    });

    test('extractAmountOnly returns null when there is nothing to find', () {
      expect(SmsParser.extractAmountOnly('Your OTP is 123456'), isNull);
      expect(SmsParser.extractAmountOnly(''), isNull);
    });

    test('parses HDFC RuPay card UPI transaction with short date and trailing @', () {
      const sms = 'Txn Rs.506.90\n'
          'On HDFC Bank Card 8174\n'
          'At SV2512112258548450219373@ \n'
          'by UPI 789574846858\n'
          'On 13-09\n'
          'Not You?\n'
          'Call 18002586161/SMS BLOCK CC 8174 to 7308080808';

      final receivedAt = DateTime(2026, 9, 13, 8, 14, 21);
      final parsed = SmsParser.parse(sms, receivedAt: receivedAt);

      expect(parsed, isNotNull);
      expect(parsed!.templateId, 'hdfc_card_upi');
      expect(parsed.amount, 506.90);
      expect(parsed.paymentType, 'HDFC Bank Card 8174');
      // Trailing @ stripped cleanly
      expect(parsed.merchant, 'SV2512112258548450219373');
      expect(parsed.reference, '789574846858');
      expect(parsed.direction, TxnDirection.debit);
      expect(parsed.hasExplicitTime, isFalse);
      // Borrows arrival time because SMS arrived on same day
      expect(parsed.date, receivedAt);
    });

    test('parses HDFC RuPay card UPI transaction with Hathway merchant name', () {
      const sms = 'Txn Rs.755.00\n'
          'On HDFC Bank Card 8174\n'
          'At hathwaymobileapp.76062993 \n'
          'by UPI 250214536533\n'
          'On 01-09\n'
          'Not You?';

      final parsed = SmsParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.templateId, 'hdfc_card_upi');
      expect(parsed.amount, 755.0);
      expect(parsed.paymentType, 'HDFC Bank Card 8174');
      expect(parsed.merchant, 'hathwaymobileapp.76062993');
      expect(parsed.reference, '250214536533');
      expect(parsed.date.month, 9);
      expect(parsed.date.day, 1);
    });

    test('parses HDFC RuPay card UPI single-line format', () {
      const sms = 'Txn Rs.506.90 On HDFC Bank Card 8174 At SV2512112258548450219373@ by UPI 789574846858 On 13-09 Not You?';
      final parsed = SmsParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.templateId, 'hdfc_card_upi');
      expect(parsed.amount, 506.90);
      expect(parsed.paymentType, 'HDFC Bank Card 8174');
      expect(parsed.merchant, 'SV2512112258548450219373');
      expect(parsed.reference, '789574846858');
    });

    test('extractInstrumentOnly extracts card or account from various message formats', () {
      const sms1 = 'Txn Rs.506.90\nOn HDFC Bank Card 8174\nAt SV2512112258548450219373@ \nby UPI 789574846858\nOn 13-09';
      expect(SmsParser.extractInstrumentOnly(sms1), 'HDFC Bank Card 8174');

      const sms2 = 'Amt Deducted! Rs.11500 from your HDFC Bank A/c XX0444 for NEFT txn';
      expect(SmsParser.extractInstrumentOnly(sms2), 'HDFC Bank A/c XX0444');

      const sms3 = 'INR 204.00 spent on YES BANK Card X2858 @UPI_GEORGE EGG CENTRE';
      expect(SmsParser.extractInstrumentOnly(sms3), 'YES BANK Card X2858');

      expect(SmsParser.extractInstrumentOnly('Your OTP is 123456'), isNull);
    });

    test('extractMerchantOnly extracts merchant name accurately', () {
      expect(SmsParser.extractMerchantOnly('spent at STARBUCKS on 22-09-2026'), 'STARBUCKS');
      expect(SmsParser.extractMerchantOnly('paid to SWIGGY. Ref 123456'), 'SWIGGY');
      expect(SmsParser.extractMerchantOnly('towards AMAZON on 10/08/26'), 'AMAZON');
      expect(SmsParser.extractMerchantOnly('random message with no merchant'), isNull);
    });

    test('extractDateOnly extracts explicit time and falls back to receivedAt', () {
      // Explicit clock time in message
      final d1 = SmsParser.extractDateOnly(
        'Spent Rs.500 at STORE on 13-08-2026, 09:21:35 am',
        receivedAt: DateTime(2026, 8, 13, 12, 0, 0),
      );
      expect(d1?.year, 2026);
      expect(d1?.month, 8);
      expect(d1?.day, 13);
      expect(d1?.hour, 9);
      expect(d1?.minute, 21);
      expect(d1?.second, 35);

      // No clock time in message, borrows receivedAt time
      final d2 = SmsParser.extractDateOnly(
        'Spent Rs.500 at STORE on 13-08-2026',
        receivedAt: DateTime(2026, 8, 14, 15, 30, 45),
      );
      expect(d2?.year, 2026);
      expect(d2?.month, 8);
      expect(d2?.day, 13);
      expect(d2?.hour, 15);
      expect(d2?.minute, 30);
      expect(d2?.second, 45);

      // Short date format with time
      final d3 = SmsParser.extractDateOnly(
        'Sent Rs.200 to FRIEND on 13-09 14:30',
        receivedAt: DateTime(2026, 9, 13, 10, 0, 0),
      );
      expect(d3?.month, 9);
      expect(d3?.day, 13);
      expect(d3?.hour, 14);
      expect(d3?.minute, 30);
    });

    test('parses various date and time formats in SMS bodies', () {
      // ISO with space
      final parsed1 = SmsParser.parse(
        'Spent Rs.122.02 From HDFC Bank Card 6824 At INNOVATIVE RETAIL CONC On 2026-08-13 07:19:26',
      );
      expect(parsed1, isNotNull);
      expect(parsed1!.date, DateTime(2026, 8, 13, 7, 19, 26));

      // With comma separator and AM/PM
      final parsed2 = SmsParser.parse(
        'INR 204.00 spent on YES BANK Card X2858 @UPI_GEORGE EGG CENTRE 13-08-2026, 09:21:35 am. Avl Lmt INR 281,496.08.',
      );
      expect(parsed2, isNotNull);
      expect(parsed2!.date, DateTime(2026, 8, 13, 9, 21, 35));

      // Month name first
      final parsed3 = SmsParser.parse(
        'INR 160.00 spent using ICICI Bank Card XX8008 on Sep 21, 2026 at 11:20:00 on AMAZON PAY IN G.',
      );
      expect(parsed3, isNotNull);
      expect(parsed3!.date, DateTime(2026, 9, 21, 11, 20, 0));
    });

    test('parses Indian Bank UPI debit with inverted date and RRN', () {
      const sms = 'Sent Rs.90.00 from A/c *4668 on 12-10-26 to M/S.RAJALAKSHMI EDUCATION SERV.RRN 316719288101.Avl Bal Rs.778.39.Not you?SMS BLOCK to 9289592895-Indian Bank.';
      final parsed = SmsParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.templateId, 'indian_bank_upi_sent');
      expect(parsed.amount, 90.00);
      expect(parsed.paymentType, 'A/c *4668');
      expect(parsed.merchant, 'RAJALAKSHMI EDUCATION SERV');
      expect(parsed.reference, '316719288101');
      expect(parsed.direction, TxnDirection.debit);
      expect(parsed.isCredit, isFalse);
    });

    test('parses HDFC multiline and single-line user templates', () {
      const multiline1 = '''Sent Rs.50000.00
From HDFC Bank A/C *2041
To B rajamalar Princy Rajama
On 12/10/26
Ref 628514613614
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808''';
      final p1 = SmsParser.parse(multiline1);
      expect(p1, isNotNull);
      expect(p1!.amount, 50000.00);
      expect(p1.merchant, 'B rajamalar Princy Rajama');
      expect(p1.reference, '628514613614');
      expect(p1.direction, TxnDirection.debit);

      const cardAlert = 'Spent Rs.2 On HDFC Bank Card 8174 At PPINAPPAUTH On 2026-10-07:20:57:59.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 8174 to 7308080808';
      final p2 = SmsParser.parse(cardAlert);
      expect(p2, isNotNull);
      expect(p2!.amount, 2.0);
      expect(p2.merchant, 'PPINAPPAUTH');
      expect(p2.direction, TxnDirection.debit);

      const multiline2 = '''Sent Rs.10.00
From HDFC Bank A/C *0444
To SSURIYA
On 11/10/26
Ref 131131522384
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808''';
      final p3 = SmsParser.parse(multiline2);
      expect(p3, isNotNull);
      expect(p3!.amount, 10.00);
      expect(p3.merchant, 'SSURIYA');
      expect(p3.reference, '131131522384');
      expect(p3.direction, TxnDirection.debit);
    });

    test('parses YES Bank card SMS template', () {
      const sms = 'INR 55.00 spent on YES BANK Card X2858 @UPI_K M PROWIN INDUSTR 09-10-2026 11:00:46 am. Avl Lmt INR 284,919.00. SMS BLKCC 2858 to 9840909000 if not you';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 55.00);
      expect(p.merchant, 'K M PROWIN INDUSTR');
      expect(p.direction, TxnDirection.debit);
    });

    test('parses SBI debited alert with space in Ref no and VPA cleaning', () {
      const sms = 'Dear Customer, your a/c no. XXXXXXXX1234 is debited by Rs. 500.00 on 12-10-26 by UPI-ZOMATO-zomato@icici. Ref no 428192019283. Available bal: Rs. 14,500.25. -SBI';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 500.00);
      expect(p.merchant, 'ZOMATO');
      expect(p.reference, '428192019283');
      expect(p.direction, TxnDirection.debit);
    });

    test('parses Acct debited with alert', () {
      const sms = 'Acct XX456 has been debited with INR 299.00 on 12-Oct-26 for UPI-SWIGGY. Bal: INR 8,210.50. Call 18002662 for dispute.';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 299.00);
      expect(p.merchant, 'SWIGGY');
      expect(p.direction, TxnDirection.debit);
    });

    test('parses Axis Bank alert with POS- prefix', () {
      const sms = 'Axis Bank Alert: Your A/C no. XXXXXX7890 is debited for INR 450.00 on 12-10-26. Info: POS-STARBUCKS. Available Balance: INR 12,300.00.';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 450.00);
      expect(p.merchant, 'STARBUCKS');
      expect(p.direction, TxnDirection.debit);
    });

    test('parses credit alerts correctly and preserves debit direction for PZCREDIT', () {
      const creditSms = 'A/c *1234 credited with INR 1,500.00 on 12-10-26 by EMPLOYER Ref 987654321';
      final pCredit = SmsParser.parse(creditSms);
      expect(pCredit, isNotNull);
      expect(pCredit!.amount, 1500.00);
      expect(pCredit.direction, TxnDirection.credit);
      expect(pCredit.isCredit, isTrue);

      // Debit alert containing "CREDIT" in merchant name must remain debit
      const pzCreditSms = 'Spent Rs.39791.72 From HDFC Bank Card x2227 At PZCREDIT9772829 On 2026-08-11:06:08:24 Bal Rs.210943.42';
      final pDebit = SmsParser.parse(pzCreditSms);
      expect(pDebit, isNotNull);
      expect(pDebit!.direction, TxnDirection.debit);
      expect(pDebit.isCredit, isFalse);
    });
  });
}
