import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';
import 'package:tu_expense_tracker/src/mobile/services/local_llm_service.dart';

void main() {
  group('LocalLlmService.parseRawJson', () {
    test('parses clean JSON debit', () {
      const json = '''
      {
        "is_transaction": true,
        "type": "debit",
        "amount": 90.0,
        "currency": "INR",
        "merchant": "M/S.RAJALAKSHMI EDUCATION SERV",
        "account": "4668",
        "reference": "316719288101",
        "date": "2026-10-12"
      }
      ''';

      final parsed = LocalLlmService.parseRawJson(json);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 90.0);
      expect(parsed.direction, TxnDirection.debit);
      expect(parsed.isCredit, false);
      expect(parsed.merchant, 'M/S.RAJALAKSHMI EDUCATION SERV');
      expect(parsed.paymentType, 'A/C *4668');
      expect(parsed.reference, '316719288101');
      expect(parsed.date.year, 2026);
      expect(parsed.date.month, 10);
      expect(parsed.date.day, 12);
    });

    test('parses clean JSON credit', () {
      const json = '''
      {
        "is_transaction": true,
        "type": "credit",
        "amount": 1500.50,
        "currency": "INR",
        "merchant": "SALARY CREDIT",
        "account": "1234",
        "reference": "UPI99220011",
        "date": "2026-10-01"
      }
      ''';

      final parsed = LocalLlmService.parseRawJson(json);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 1500.50);
      expect(parsed.direction, TxnDirection.credit);
      expect(parsed.isCredit, true);
      expect(parsed.merchant, 'SALARY CREDIT');
      expect(parsed.paymentType, 'A/C *1234');
      expect(parsed.reference, 'UPI99220011');
    });

    test('extracts JSON surrounded by markdown codeblocks or conversational text', () {
      const rawText = '''
      Here is the extracted transaction details from the bank notification:
      ```json
      {
        "is_transaction": true,
        "type": "debit",
        "amount": "50,000.00",
        "currency": "INR",
        "merchant": "B rajamalar Princy Rajama",
        "account": "2041",
        "reference": "628514613614",
        "date": "2026-10-12"
      }
      ```
      Hope that helps!
      ''';

      final parsed = LocalLlmService.parseRawJson(rawText);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 50000.0);
      expect(parsed.direction, TxnDirection.debit);
      expect(parsed.merchant, 'B rajamalar Princy Rajama');
      expect(parsed.paymentType, 'A/C *2041');
      expect(parsed.reference, '628514613614');
    });

    test('returns null when is_transaction is false (OTP / promo SMS)', () {
      const rawText = '''
      {
        "is_transaction": false,
        "type": null,
        "amount": null,
        "merchant": null
      }
      ''';

      final parsed = LocalLlmService.parseRawJson(rawText);
      expect(parsed, isNull);
    });

    test('returns null on invalid or empty JSON', () {
      expect(LocalLlmService.parseRawJson(''), isNull);
      expect(LocalLlmService.parseRawJson('This is not JSON at all'), isNull);
      expect(LocalLlmService.parseRawJson('{ bad json }'), isNull);
    });

    test('handles fallback date when date is missing or invalid', () {
      final fallback = DateTime(2026, 8, 15, 10, 30);
      const json = '''
      {
        "is_transaction": true,
        "type": "debit",
        "amount": 25.0,
        "merchant": "CHAI POINT"
      }
      ''';

      final parsed = LocalLlmService.parseRawJson(json, fallbackDate: fallback);
      expect(parsed, isNotNull);
      expect(parsed!.amount, 25.0);
      expect(parsed.date, fallback);
      expect(parsed.paymentType, 'Card/UPI');
    });
  });
}
