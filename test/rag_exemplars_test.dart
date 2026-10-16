import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/rag_exemplars.dart';

void main() {
  group('RagExemplars', () {
    test('curated list has valid exemplars with expected JSON structure', () {
      expect(RagExemplars.curated, isNotEmpty);
      for (final ex in RagExemplars.curated) {
        expect(ex.id, isNotEmpty);
        expect(ex.bank, isNotEmpty);
        expect(ex.rawSms, isNotEmpty);
        expect(ex.expectedJson['is_transaction'], isTrue);
        expect(ex.expectedJson.containsKey('type'), isTrue);
        expect(ex.expectedJson.containsKey('amount'), isTrue);
        expect(ex.expectedJson.containsKey('merchant'), isTrue);
      }
    });

    test('findBestExemplars matches HDFC alert accurately', () {
      const sms = 'Spent Rs.350 on HDFC Card ending 1234 at Starbucks on 12-Oct.';
      final matches = RagExemplars.findBestExemplars(sms, limit: 1);

      expect(matches, hasLength(1));
      expect(matches.first.bank, 'HDFC Bank');
      expect(matches.first.id, 'hdfc_card_debit');
    });

    test('findBestExemplars matches credit/refund accurately', () {
      const sms = 'Your A/C *5555 is credited with Rs 499 towards Refund.';
      final matches = RagExemplars.findBestExemplars(sms, limit: 1);

      expect(matches, hasLength(1));
      expect(matches.first.expectedJson['type'], 'credit');
    });

    test('findBestExemplars handles empty input gracefully', () {
      final matches = RagExemplars.findBestExemplars('   ');
      expect(matches, isEmpty);
    });
  });
}
