/// Helper for preparing and launching pre-filled GitHub Issue contributions.
///
/// Enables zero-cloud, 100% transparent community contributions of sanitized bank SMS formats.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

class GitHubContributionHelper {
  GitHubContributionHelper._();

  static const String repoOwner = 'Jayachandran-jayy';
  static const String repoName = 'TU-Expense-Manager';
  static const String readmeGuideUrl =
      'https://github.com/$repoOwner/$repoName#-contributing-bank-sms-formats-improving-local-ai--rag';

  static const MethodChannel _telephonyChannel = MethodChannel('com.tu.expense.manager/telephony');

  /// Generates the Markdown body for the GitHub issue.
  static String generateIssueBody({
    required String sanitizedSms,
    required String bankHint,
    required String transactionType,
    required double? amount,
    required String merchant,
    String? account,
    String? reference,
    String? date,
  }) {
    final Map<String, dynamic> jsonFormat = <String, dynamic>{
      'is_transaction': true,
      'type': transactionType.toLowerCase(),
      'amount': amount,
      'currency': 'INR',
      'merchant': merchant,
      'account': account,
      'reference': reference ?? '[MASKED]',
      'date': date,
    };

    final String prettyJson = const JsonEncoder.withIndent('  ').convert(jsonFormat);

    return '''
### 🏦 Bank SMS Format Contribution

- **Bank / Provider**: ${bankHint.isEmpty ? 'Unknown' : bankHint}
- **Transaction Type**: $transactionType
- **Extracted Merchant**: $merchant
- **Extracted Amount**: ${amount != null ? '₹$amount' : 'N/A'}

#### 📄 Sanitized SMS (Accounts, balances & refs masked)
```text
$sanitizedSms
```

#### 🎯 Expected JSON Extraction
```json
$prettyJson
```

---
*Submitted voluntarily from TU Expense Tracker to train offline on-device AI and expand code-baked RAG exemplars.*
''';
  }

  /// Builds the pre-filled GitHub Issue URI.
  static Uri buildIssueUri({
    required String sanitizedSms,
    required String bankHint,
    required String transactionType,
    required double? amount,
    required String merchant,
    String? account,
    String? reference,
    String? date,
  }) {
    final String title = '[Format Contribution]: ${bankHint.isNotEmpty ? bankHint : merchant} ($transactionType)';
    final String body = generateIssueBody(
      sanitizedSms: sanitizedSms,
      bankHint: bankHint,
      transactionType: transactionType,
      amount: amount,
      merchant: merchant,
      account: account,
      reference: reference,
      date: date,
    );

    return Uri.https(
      'github.com',
      '/$repoOwner/$repoName/issues/new',
      <String, String>{
        'title': title,
        'body': body,
        'labels': 'dataset-contribution,ai-rag',
      },
    );
  }

  /// Opens any HTTP/HTTPS URL in the system browser using the native telephony channel.
  static Future<bool> openUrl(String url) async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? res = await _telephonyChannel.invokeMethod<bool>('openUrl', <String, Object?>{'url': url});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the README contribution guide in the system browser.
  static Future<bool> openReadmeGuide() => openUrl(readmeGuideUrl);

  /// Copies sanitized payload to clipboard and opens the pre-filled GitHub issue in the browser.
  static Future<bool> launchContributionFlow({
    required String sanitizedSms,
    required String bankHint,
    required String transactionType,
    required double? amount,
    required String merchant,
    String? account,
    String? reference,
    String? date,
  }) async {
    final String body = generateIssueBody(
      sanitizedSms: sanitizedSms,
      bankHint: bankHint,
      transactionType: transactionType,
      amount: amount,
      merchant: merchant,
      account: account,
      reference: reference,
      date: date,
    );

    // 1. Copy snippet to clipboard for convenience
    await Clipboard.setData(ClipboardData(text: body));

    // 2. Open GitHub Issue in browser
    final Uri uri = buildIssueUri(
      sanitizedSms: sanitizedSms,
      bankHint: bankHint,
      transactionType: transactionType,
      amount: amount,
      merchant: merchant,
      account: account,
      reference: reference,
      date: date,
    );

    return await openUrl(uri.toString());
  }
}
