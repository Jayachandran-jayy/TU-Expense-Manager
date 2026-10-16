import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/mobile/services/local_rag_retriever.dart';

void main() {
  group('LocalRagRetriever', () {
    final retriever = LocalRagRetriever.instance;

    test('buildAugmentedSystemPrompt includes base instructions and matched exemplars', () async {
      const sms = 'Alert: Rs 550 spent on HDFC Card ending 1234 at Swiggy on 15-Oct.';
      final prompt = await retriever.buildAugmentedSystemPrompt(sms);

      expect(prompt, contains('You are an expert bank transaction parser'));
      expect(prompt, contains('[Reference Examples]'));
      expect(prompt, contains('HDFC Bank'));
      expect(prompt, contains('"is_transaction": true'));
      expect(prompt, contains('"type": "debit"'));
    });

    test('buildAugmentedSystemPrompt handles refund and credit queries', () async {
      const sms = 'Your A/c *8888 credited with Rs.250 towards refund from Zomato.';
      final prompt = await retriever.buildAugmentedSystemPrompt(sms);

      expect(prompt, contains('credit'));
      expect(prompt, contains('[Reference Examples]'));
    });
  });
}
