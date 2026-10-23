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

    test('masks UPI IDs, PAN, and Australian BSB and account numbers', () {
      const sms = 'Paid Rs 200 to shop@okhdfcbank. PAN ABCDE1234F. BSB 062-000 Acc 12345678.';
      final result = sanitizer.sanitize(sms);

      expect(result.sanitizedText, contains('[UPI_ID]'));
      expect(result.sanitizedText, contains('[PAN]'));
      expect(result.sanitizedText, contains('[BSB]'));
      expect(result.sanitizedText, contains('Acc *XXXX'));
      expect(result.sanitizedText, isNot(contains('shop@okhdfcbank')));
      expect(result.sanitizedText, isNot(contains('ABCDE1234F')));
      expect(result.sanitizedText, isNot(contains('062-000')));
      expect(result.sanitizedText, contains('Rs 200'));
      expect(result.detectedEntities, containsAll(<String>['UPI ID', 'PAN', 'BSB']));
    });

    test('sanitized output has nothing left to redact', () {
      const sms = 'Your OTP is 482910. A/c 54321 debited Rs 500. Bal: Rs 12,000. Mail help@bank.com';
      final once = sanitizer.sanitize(sms);
      final twice = sanitizer.sanitize(once.sanitizedText);

      expect(twice.hasRedactions, isFalse);
      expect(twice.sanitizedText, once.sanitizedText);
    });

    test('handles empty input gracefully', () {
      final result = sanitizer.sanitize('   ');
      expect(result.hasRedactions, isFalse);
      expect(result.maskedCount, 0);
    });
  });
}
