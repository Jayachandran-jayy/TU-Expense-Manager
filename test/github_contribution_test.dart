import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/mobile/services/github_contribution_helper.dart';

void main() {
  group('GitHubContributionHelper', () {
    test('generateIssueBody builds formatted markdown with sanitized text and json', () {
      final body = GitHubContributionHelper.generateIssueBody(
        sanitizedSms: 'Rs 450 spent on HDFC Card ending *XXXX at Swiggy.',
        bankHint: 'HDFC Bank',
        transactionType: 'Debit',
        amount: 450.0,
        merchant: 'Swiggy',
        account: '*XXXX',
        reference: '[MASKED]',
        date: '2026-10-16',
      );

      expect(body, contains('**Bank / Provider**: HDFC Bank'));
      expect(body, contains('**Transaction Type**: Debit'));
      expect(body, contains('**Extracted Merchant**: Swiggy'));
      expect(body, contains('₹450.0'));
      expect(body, contains('Rs 450 spent on HDFC Card ending *XXXX'));
      expect(body, contains('"is_transaction": true'));
      expect(body, contains('"merchant": "Swiggy"'));
    });

    test('buildIssueUri generates valid GitHub issue URL with query parameters', () {
      final uri = GitHubContributionHelper.buildIssueUri(
        sanitizedSms: 'Test SMS',
        bankHint: 'SBI',
        transactionType: 'Debit',
        amount: 100.0,
        merchant: 'Chai',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.path, '/Jayachandran-jayy/TU-Expense-Manager/issues/new');
      expect(uri.queryParameters['title'], contains('[Format Contribution]: SBI (Debit)'));
      expect(uri.queryParameters['labels'], contains('dataset-contribution'));
    });
  });
}
