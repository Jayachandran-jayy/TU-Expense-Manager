/// Helper for preparing and launching pre-filled GitHub Issue contributions.
///
/// Enables zero-cloud, 100% transparent community contributions of sanitized bank SMS formats.
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Holds sanitized system diagnostics for bug reporting.
class DeviceDiagnostics {
  final String appVersion;
  final String appBuild;
  final String deviceModel;
  final String osVersion;
  final int? sdkInt;

  const DeviceDiagnostics({
    required this.appVersion,
    required this.appBuild,
    required this.deviceModel,
    required this.osVersion,
    this.sdkInt,
  });

  String get summary {
    final os = sdkInt != null ? 'Android $osVersion (API $sdkInt)' : osVersion;
    return '$deviceModel • $os • v$appVersion${appBuild.isNotEmpty ? '+$appBuild' : ''}';
  }
}

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
- **Extracted Amount**: ${amount != null ? '₹${amount.toStringAsFixed(2)}' : 'N/A'}

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

  /// Copies a masked statement excerpt to the clipboard and opens a pre-filled
  /// GitHub issue for it. Only text the user has reviewed is sent; never the PDF.
  static Future<bool> launchStatementContribution({
    required String excerpt,
    required String bankHint,
  }) async {
    final String body = '''
### 🧾 Bank Statement Format Contribution

- **Bank / Provider**: ${bankHint.isEmpty ? 'Unknown' : bankHint}

#### 📄 Masked statement rows (accounts, references & balances masked)
```text
$excerpt
```

---
*Submitted voluntarily from TU Expense Tracker so this statement layout can be read automatically.*
''';
    await Clipboard.setData(ClipboardData(text: body));
    final Uri uri = Uri.https('github.com', '/$repoOwner/$repoName/issues/new', <String, String>{
      'title': '[Statement Format]: ${bankHint.isEmpty ? 'Unknown bank' : bankHint}',
      'body': body,
      'labels': 'dataset-contribution',
    });
    return await openUrl(uri.toString());
  }

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

  /// Fetches system and device diagnostics for bug reporting.
  static Future<DeviceDiagnostics> fetchDeviceDiagnostics({
    String? appVersion,
    String? appBuild,
  }) async {
    String version = appVersion ?? 'Unknown';
    String build = appBuild ?? '';
    if (appVersion == null) {
      try {
        final info = await PackageInfo.fromPlatform();
        version = info.version;
        build = info.buildNumber;
      } catch (_) {}
    }

    String model = Platform.operatingSystem;
    String os = Platform.operatingSystemVersion;
    int? sdk;

    if (Platform.isAndroid) {
      try {
        final Map<dynamic, dynamic>? res = await _telephonyChannel
            .invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
        if (res != null) {
          final mfg = res['manufacturer']?.toString() ?? '';
          final mdl = res['model']?.toString() ?? '';
          model = mfg.isNotEmpty ? '$mfg $mdl'.trim() : mdl;
          os = res['androidVersion']?.toString() ?? os;
          sdk = res['sdkInt'] as int?;
        }
      } catch (_) {}
    }

    return DeviceDiagnostics(
      appVersion: version,
      appBuild: build,
      deviceModel: model.isNotEmpty ? model : 'Unknown Device',
      osVersion: os,
      sdkInt: sdk,
    );
  }

  /// Generates the Markdown body for a GitHub bug report issue.
  static String generateBugReportBody({
    String? title,
    required String description,
    String? stepsToReproduce,
    required DeviceDiagnostics diagnostics,
  }) {
    final buffer = StringBuffer();
    if (title != null && title.trim().isNotEmpty) {
      final cleanTitle = title.trim();
      final headerTitle = cleanTitle.toLowerCase().startsWith('[bug')
          ? cleanTitle
          : cleanTitle;
      buffer.writeln('### 🐛 Bug Report: $headerTitle\n');
    } else {
      buffer.writeln('### 🐛 Bug Report\n');
    }
    buffer.writeln('#### Description');
    buffer.writeln(description.trim());
    buffer.writeln();

    if (stepsToReproduce != null && stepsToReproduce.trim().isNotEmpty) {
      buffer.writeln('#### Steps to Reproduce');
      buffer.writeln(stepsToReproduce.trim());
      buffer.writeln();
    }

    buffer.writeln('#### System Diagnostics');
    buffer.writeln('- **App Version**: ${diagnostics.appVersion}${diagnostics.appBuild.isNotEmpty ? ' (build ${diagnostics.appBuild})' : ''}');
    buffer.writeln('- **Device**: ${diagnostics.deviceModel}');
    final osText = diagnostics.sdkInt != null
        ? 'Android ${diagnostics.osVersion} (API ${diagnostics.sdkInt})'
        : diagnostics.osVersion;
    buffer.writeln('- **OS**: $osText');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln('*Reported voluntarily via TU Expense Tracker.*');

    return buffer.toString();
  }

  /// Builds the pre-filled GitHub Issue URI for a bug report.
  static Uri buildBugReportUri({
    required String title,
    required String body,
  }) {
    final cleanTitle = title.trim();
    final String issueTitle = cleanTitle.toLowerCase().startsWith('[bug')
        ? cleanTitle
        : '[Bug Report]: $cleanTitle';

    return Uri.https(
      'github.com',
      '/$repoOwner/$repoName/issues/new',
      <String, String>{
        'title': issueTitle,
        'body': body,
        'labels': 'bug',
      },
    );
  }

  /// Copies bug report markdown to clipboard and opens the pre-filled GitHub issue in the browser.
  static Future<bool> launchBugReportFlow({
    required String title,
    required String description,
    String? stepsToReproduce,
    required DeviceDiagnostics diagnostics,
  }) async {
    final String body = generateBugReportBody(
      title: title,
      description: description,
      stepsToReproduce: stepsToReproduce,
      diagnostics: diagnostics,
    );

    // 1. Copy snippet to clipboard for convenience
    Clipboard.setData(ClipboardData(text: body));

    // 2. Open GitHub Issue in browser
    final Uri uri = buildBugReportUri(
      title: title,
      body: body,
    );

    return await openUrl(uri.toString());
  }
}
