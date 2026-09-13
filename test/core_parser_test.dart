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
  });
}
