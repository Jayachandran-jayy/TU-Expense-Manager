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
  });
}
