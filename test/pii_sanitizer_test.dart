import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/pii_sanitizer.dart';

void main() {
  group('PiiSanitizer', () {
    const sanitizer = PiiSanitizer();

    test('masks bank account numbers and card numbers', () {
      const sms = 'Alert: Rs 500 debited from A/c 54321 on 12-Oct. Card ending 8174 used.';
      final result = sanitizer.sanitize(sms);

      expect(result.hasRedactions, isTrue);
      expect(result.sanitizedText, contains('A/c *XXXX'));
      expect(result.sanitizedText, contains('Card ending *XXXX'));
      expect(result.sanitizedText, contains('Rs 500 debited'));
      expect(result.detectedEntities, contains('Account / Card Number'));
    });

    test('masks balances while keeping transaction amount intact', () {
      const sms = 'Txn of Rs.1,250.00 at SWIGGY. Avail Bal: Rs 45,210.50. Ref: 428192847192.';
      final result = sanitizer.sanitize(sms);

      expect(result.hasRedactions, isTrue);
      expect(result.sanitizedText, contains('Rs.1,250.00 at SWIGGY'));
      expect(result.sanitizedText, contains('Avail Bal: Rs [MASKED]'));
      expect(result.sanitizedText, contains('Ref: [MASKED]'));
      expect(result.detectedEntities, contains('Account Balance'));
      expect(result.detectedEntities, contains('Reference / UTR / RRN'));
    });

    test('masks phone numbers, OTPs, and emails', () {
      const sms = 'Your OTP is 482910 for txn of Rs 90. Contact 9876543210 or help@bank.com for query.';
      final result = sanitizer.sanitize(sms);

      expect(result.sanitizedText, contains('[OTP]'));
      expect(result.sanitizedText, contains('[PHONE]'));
      expect(result.sanitizedText, contains('[EMAIL]'));
      expect(result.sanitizedText, isNot(contains('482910')));
      expect(result.sanitizedText, isNot(contains('9876543210')));
      expect(result.sanitizedText, isNot(contains('help@bank.com')));
    });

    test('handles empty input gracefully', () {
      final result = sanitizer.sanitize('   ');
      expect(result.hasRedactions, isFalse);
      expect(result.maskedCount, 0);
    });
  });
}
