// Triage, diagnose, and scaffold community SMS format contributions from GitHub issues.
//
// Usage:
//   dart run tool/dev/triage_sms_issues.dart [options]
//
// Options:
//   --issue=<number>   Triage a specific issue (e.g. --issue=95)
//   --all              Include closed issues (default is open issues only)
//   --scaffold         Generate code snippets for parser, RAG exemplars, and tests
//   --reply            Prompt to post acceptance or rejection comment to GitHub
//   --help, -h         Show help
// ignore_for_file: avoid_print
library;

import 'dart:convert';
import 'dart:io';

import 'package:tu_expense_tracker/src/core/parser.dart';

class ContributionIssue {
  final int number;
  final String title;
  final String state;
  final String bank;
  final String type;
  final String merchant;
  final String amount;
  final String sanitizedSms;
  final Map<String, dynamic>? expectedJson;
  final String rawBody;

  ContributionIssue({
    required this.number,
    required this.title,
    required this.state,
    required this.bank,
    required this.type,
    required this.merchant,
    required this.amount,
    required this.sanitizedSms,
    required this.expectedJson,
    required this.rawBody,
  });

  static ContributionIssue? parse(Map<String, dynamic> map) {
    final int number = map['number'] as int? ?? 0;
    final String title = map['title'] as String? ?? '';
    final String state = map['state'] as String? ?? 'OPEN';
    final String body = map['body'] as String? ?? '';

    if (!title.contains('[Format Contribution]:') &&
        !body.contains('### 🏦 Bank SMS Format Contribution')) {
      return null;
    }

    String extractField(String fieldName) {
      final RegExp regex = RegExp(
        '[-•*]\\s*\\**${RegExp.escape(fieldName)}\\**:\\s*(.*)',
        caseSensitive: false,
      );
      final RegExpMatch? match = regex.firstMatch(body);
      return match != null ? match.group(1)?.trim() ?? '' : '';
    }

    final String bank = extractField('Bank / Provider');
    final String type = extractField('Transaction Type');
    final String merchant = extractField('Extracted Merchant');
    final String amount = extractField('Extracted Amount');

    // Extract sanitized SMS
    String sanitizedSms = '';
    final RegExp smsRegex = RegExp(
      r'####\s*📄\s*Sanitized\s*SMS[^\n]*\n+([\s\S]*?)(?=####\s*🎯\s*Expected\s*JSON|--------|$)',
      caseSensitive: false,
    );
    final RegExpMatch? smsMatch = smsRegex.firstMatch(body);
    if (smsMatch != null) {
      sanitizedSms = smsMatch.group(1)?.trim() ?? '';
      // Strip markdown code fences if present
      if (sanitizedSms.startsWith('```')) {
        sanitizedSms = sanitizedSms.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      }
      if (sanitizedSms.endsWith('```')) {
        sanitizedSms = sanitizedSms.substring(0, sanitizedSms.length - 3).trim();
      }
    }

    // Extract expected JSON
    Map<String, dynamic>? expectedJson;
    final RegExp jsonRegex = RegExp(
      r'####\s*🎯\s*Expected\s*JSON[^\n]*\n+([\s\S]*?)(?=--------|$)',
      caseSensitive: false,
    );
    final RegExpMatch? jsonMatch = jsonRegex.firstMatch(body);
    if (jsonMatch != null) {
      String jsonText = jsonMatch.group(1)?.trim() ?? '';
      if (jsonText.startsWith('```')) {
        jsonText = jsonText.replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '');
      }
      if (jsonText.endsWith('```')) {
        jsonText = jsonText.substring(0, jsonText.length - 3).trim();
      }
      try {
        expectedJson = json.decode(jsonText) as Map<String, dynamic>?;
      } catch (_) {}
    }

    return ContributionIssue(
      number: number,
      title: title,
      state: state,
      bank: bank,
      type: type,
      merchant: merchant,
      amount: amount,
      sanitizedSms: sanitizedSms,
      expectedJson: expectedJson,
      rawBody: body,
    );
  }
}

class DiagnosticResult {
  final bool isValidTransaction;
  final String? invalidReason;
  final bool isAlreadyRecognized;
  final ParsedSms? parsedResult;
  final double? extractedAmount;
  final bool hasDebitKeyword;
  final bool hasCreditKeyword;
  final bool hasDateMatch;
  final List<String> dateIssues;
  final String instrumentIssue;
  final String bottleneckSummary;

  DiagnosticResult({
    required this.isValidTransaction,
    this.invalidReason,
    required this.isAlreadyRecognized,
    this.parsedResult,
    this.extractedAmount,
    required this.hasDebitKeyword,
    required this.hasCreditKeyword,
    required this.hasDateMatch,
    required this.dateIssues,
    required this.instrumentIssue,
    required this.bottleneckSummary,
  });
}

DiagnosticResult diagnoseSms(String body) {
  final String lower = body.toLowerCase();

  // 1. Transaction validity check
  // Alerts that are not completed transactions (mandates due, standing instructions due, OTPs, warnings)
  if (lower.contains('is due by') ||
      lower.contains('due date') ||
      lower.contains('to be debited') ||
      lower.contains('will be debited') ||
      lower.contains('scheduled on') ||
      (lower.contains('standing instruction') && lower.contains('is due'))) {
    return DiagnosticResult(
      isValidTransaction: false,
      invalidReason: 'SMS indicates a scheduled or future payment ("to be debited" / "is due by"), not a completed transaction.',
      isAlreadyRecognized: false,
      hasDebitKeyword: false,
      hasCreditKeyword: false,
      hasDateMatch: false,
      dateIssues: const <String>[],
      instrumentIssue: '',
      bottleneckSummary: 'Not a completed transaction alert.',
    );
  }

  // 2. Try standard parser
  final ParsedSms? parsed = SmsParser.parse(body);
  if (parsed != null) {
    return DiagnosticResult(
      isValidTransaction: true,
      isAlreadyRecognized: true,
      parsedResult: parsed,
      extractedAmount: parsed.amount,
      hasDebitKeyword: parsed.direction == TxnDirection.debit,
      hasCreditKeyword: parsed.direction == TxnDirection.credit,
      hasDateMatch: true,
      dateIssues: const <String>[],
      instrumentIssue: '',
      bottleneckSummary: 'Already recognized by template "${parsed.templateId}".',
    );
  }

  // 3. Deep failure diagnosis
  final double? amount = SmsParser.extractAmountOnly(body);

  final bool hasDebit = RegExp(r'\b(debited|spent|paid|transferred|deducted|sent|bill paid)\b', caseSensitive: false).hasMatch(body);
  final bool hasCredit = RegExp(r'\b(credited|received|deposited|refunded)\b', caseSensitive: false).hasMatch(body);

  // Check date patterns
  final List<String> dateIssues = <String>[];
  final bool hasOrdinalDate = RegExp(r'\b\d{1,2}(?:st|nd|rd|th)\b', caseSensitive: false).hasMatch(body);
  if (hasOrdinalDate) {
    dateIssues.add('Contains ordinal date suffix (e.g. "06th") not supported by current date regex.');
  }
  final bool hasApostropheInDate = RegExp(r"[A-Za-z]+'\s*\d{2,4}|\b'\d{2}\b").hasMatch(body);
  if (hasApostropheInDate) {
    dateIssues.add("Contains apostrophe in month/year (e.g. \"Oct' 2026\").");
  }
  final bool hasCommaInDate = RegExp(r'\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4},\s*\d{1,2}:\d{2}').hasMatch(body);
  if (hasCommaInDate) {
    dateIssues.add('Contains comma-separated timestamp (e.g. "21-10-26, 13:52:41").');
  }

  // Check instrument masking
  String instrumentIssue = '';
  if (RegExp(r'(?:A/[Cc]|a/c|Account|Card)\s*(?:no\.?)?\s*x{4,}', caseSensitive: false).hasMatch(body) &&
      !RegExp(r'(?:A/[Cc]|a/c|Account|Card)\s*(?:no\.?)?\s*[Xx*]*\d+').hasMatch(body)) {
    instrumentIssue = 'Account/card has letters only (e.g. "xxxxxx") with no digits captured.';
  }

  // Bottleneck summary
  final List<String> reasons = <String>[];
  if (amount == null) reasons.add('Amount regex failed');
  if (!hasDebit && !hasCredit) reasons.add('No debit/credit direction keyword');
  if (dateIssues.isNotEmpty) reasons.addAll(dateIssues);
  if (instrumentIssue.isNotEmpty) reasons.add(instrumentIssue);

  if (body.contains('via Debit Mandate')) {
    reasons.add('Preposition "via Debit Mandate for" is unhandled in general debit template.');
  }
  if (body.contains('UPI/P2M/')) {
    reasons.add('Multi-line Axis UPI format "UPI/P2M/<ref>/<merchant>" not matched.');
  }

  final String bottleneck = reasons.isEmpty ? 'Message structure does not match any anchored template.' : reasons.join('; ');

  return DiagnosticResult(
    isValidTransaction: true,
    isAlreadyRecognized: false,
    extractedAmount: amount,
    hasDebitKeyword: hasDebit,
    hasCreditKeyword: hasCredit,
    hasDateMatch: dateIssues.isEmpty,
    dateIssues: dateIssues,
    instrumentIssue: instrumentIssue,
    bottleneckSummary: bottleneck,
  );
}

void printScaffolding(ContributionIssue issue, DiagnosticResult diag) {
  final String cleanBankId = issue.bank
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  final String typeLower = issue.type.toLowerCase().contains('credit') ? 'credit' : 'debit';
  final String templateId = '${cleanBankId}_$typeLower';

  print('\n📦 Proposed Scaffolding for Issue #${issue.number}:');
  print('----------------------------------------------------');
  print('1. RAG Exemplar (`lib/src/core/rag_exemplars.dart`):');
  print('```dart');
  final List<String> keywords = [
    ...issue.bank.toLowerCase().split(RegExp(r'\s+')),
    typeLower,
    'rs',
    'inr',
  ].where((k) => k.length >= 2).toSet().toList();

  final Map<String, dynamic> expected = {
    'is_transaction': true,
    'type': typeLower,
    'amount': double.tryParse(issue.amount.replaceAll(RegExp(r'[^\d.]'), '')) ?? diag.extractedAmount ?? 0.0,
    'currency': 'INR',
    'merchant': issue.merchant.isNotEmpty ? issue.merchant : 'Unknown',
    'account': null,
    'reference': '[MASKED]',
    'date': null,
  };

  final String escapedSms = issue.sanitizedSms.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n');

  print('    RagExemplar(');
  print("      id: '$templateId',");
  print("      bank: '${issue.bank}',");
  print('      keywords: <String>${json.encode(keywords)},');
  print("      rawSms: '$escapedSms',");
  print('      expectedJson: <String, dynamic>${json.encode(expected)},');
  print('    ),');
  print('```');

  print('\n2. Unit Test (`test/core_parser_test.dart`):');
  print('```dart');
  print("  test('parse: ${issue.bank} $typeLower (Issue #${issue.number})', () {");
  print("    final ParsedSms? parsed = SmsParser.parse(");
  print("      '''${issue.sanitizedSms}''',");
  print('    );');
  print('    expect(parsed, isNotNull);');
  if (diag.extractedAmount != null) {
    print('    expect(parsed!.amount, ${diag.extractedAmount});');
  }
  print("    expect(parsed!.direction, TxnDirection.$typeLower);");
  if (issue.merchant.isNotEmpty) {
    print("    expect(parsed.merchant, contains('${issue.merchant.split('_').first}'));");
  }
  print('  });');
  print('```');
}

Future<void> handleReply(ContributionIssue issue, DiagnosticResult diag) async {
  String defaultReply = '';
  if (diag.isAlreadyRecognized) {
    final String dateStr = diag.parsedResult != null
        ? '${diag.parsedResult!.date.year}-${diag.parsedResult!.date.month.toString().padLeft(2, '0')}-${diag.parsedResult!.date.day.toString().padLeft(2, '0')}'
        : '';
    final String refStr = (diag.parsedResult?.reference.isNotEmpty ?? false)
        ? ', and reference (${diag.parsedResult!.reference})'
        : '';

    defaultReply = '''Thank you for the contribution!

This format is already recognized by our SMS parser (under the `${diag.parsedResult?.templateId}` template), which parses the amount (₹${diag.parsedResult?.amount}), date ($dateStr), merchant ("${diag.parsedResult?.merchant}")$refStr.

If this transaction is not showing up or not being recognized in your app's transaction list, please let us know with details (such as whether it landed in your Unadded SMS inbox) so we can investigate further.

We will keep this issue open for **7 days** for any comments or updates. If there is no further reply within 7 days, it will be automatically closed.''';
  } else if (diag.isValidTransaction) {
    defaultReply =
        'Thank you for the contribution! This format has been accepted. To get it reflected immediately once merged, you can download the latest build from GitHub Releases or wait for the next F-Droid release.';
  } else {
    defaultReply =
        'This is not a valid transaction because the SMS explicitly states ${diag.invalidReason ?? "a non-completed transaction"}. We can only add successfully debited SMS transactions.';
  }

  print('\n💬 Draft Comment for Issue #${issue.number}:');
  print('"""\n$defaultReply\n"""');
  stdout.write('Post this comment to GitHub Issue #${issue.number}? (y/N): ');
  final String? input = stdin.readLineSync();
  if (input?.trim().toLowerCase() == 'y') {
    final ProcessResult res = await Process.run(
      'gh',
      ['issue', 'comment', issue.number.toString(), '--body', defaultReply],
    );
    if (res.exitCode == 0) {
      print('✅ Successfully posted comment to Issue #${issue.number}.');
    } else {
      print('❌ Failed to post comment: ${res.stderr}');
    }
  } else {
    print('⏭️ Comment skipped.');
  }
}

Future<void> main(List<String> args) async {
  bool includeAll = false;
  int? targetIssue;
  bool generateScaffold = false;
  bool shouldReply = false;

  for (final String arg in args) {
    if (arg == '--all') {
      includeAll = true;
    } else if (arg.startsWith('--issue=')) {
      targetIssue = int.tryParse(arg.substring('--issue='.length));
    } else if (arg == '--scaffold') {
      generateScaffold = true;
    } else if (arg == '--reply') {
      shouldReply = true;
    } else if (arg == '--help' || arg == '-h') {
      print('''
SMS Contribution Triage Tool
Scans, diagnoses, and scaffolds community SMS format contributions from GitHub issues.

Usage:
  dart run tool/dev/triage_sms_issues.dart [options]

Options:
  --issue=<number>   Triage a specific issue (e.g. --issue=95)
  --all              Include closed issues (default is open issues only)
  --scaffold         Generate code snippets for parser, RAG exemplars, and tests
  --reply            Prompt to post acceptance or rejection comment to GitHub
  --help, -h         Show help
''');
      return;
    }
  }

  // 1. Fetch issues using gh CLI
  print('🔍 Fetching format contribution issues from GitHub...');
  final List<String> ghArgs = [
    'issue',
    'list',
    '--state',
    (includeAll || targetIssue != null) ? 'all' : 'open',
    '--json',
    'number,title,body,state,labels',
    '--limit',
    '100',
  ];

  final ProcessResult result = await Process.run('gh', ghArgs);
  if (result.exitCode != 0) {
    print('❌ Failed to run gh CLI: ${result.stderr}');
    print('Please ensure `gh auth status` is authenticated.');
    exit(1);
  }

  final List<dynamic> rawList = json.decode(result.stdout as String) as List<dynamic>;
  final List<ContributionIssue> issues = rawList
      .map((item) => ContributionIssue.parse(item as Map<String, dynamic>))
      .whereType<ContributionIssue>()
      .where((issue) => targetIssue == null || issue.number == targetIssue)
      .toList();

  if (issues.isEmpty) {
    print('No format contribution issues found matching criteria.');
    return;
  }

  print('Found ${issues.length} format contribution issue(s).\n');

  for (final ContributionIssue issue in issues) {
    print('══════════════════════════════════════════════════════════════════════');
    print('📋 Issue #${issue.number} [${issue.state}]: ${issue.title}');
    print('   Bank: ${issue.bank} | Type: ${issue.type} | Amount: ${issue.amount}');
    print('   Merchant: ${issue.merchant}');
    print('──────────────────────────────────────────────────────────────────────');
    print('📄 Sanitized SMS:');
    print('   ${issue.sanitizedSms.replaceAll('\n', '\n   ')}');
    print('──────────────────────────────────────────────────────────────────────');

    final DiagnosticResult diag = diagnoseSms(issue.sanitizedSms);

    if (!diag.isValidTransaction) {
      print('❌ Status: INVALID TRANSACTION');
      print('   Reason: ${diag.invalidReason}');
    } else if (diag.isAlreadyRecognized) {
      print('✅ Status: ALREADY RECOGNIZED');
      print('   Template: ${diag.parsedResult?.templateId}');
      print('   Parsed Amount: ₹${diag.parsedResult?.amount}');
      print('   Direction: ${diag.parsedResult?.direction.name}');
      print('   Merchant: "${diag.parsedResult?.merchant}"');
      print('   Date: ${diag.parsedResult?.date}');
    } else {
      print('⚠️ Status: VALID TRANSACTION (UNRECOGNIZED)');
      print('   Diagnosis Breakdown:');
      print('   • Amount Extracted: ${diag.extractedAmount != null ? "₹${diag.extractedAmount}" : "FAILED"}');
      print('   • Direction Keyword: ${diag.hasDebitKeyword ? "Debit" : (diag.hasCreditKeyword ? "Credit" : "NONE")}');
      print('   • Date Status: ${diag.dateIssues.isEmpty ? "OK" : diag.dateIssues.join(", ")}');
      if (diag.instrumentIssue.isNotEmpty) {
        print('   • Instrument Status: ${diag.instrumentIssue}');
      }
      print('   • Bottleneck: ${diag.bottleneckSummary}');

      if (generateScaffold) {
        printScaffolding(issue, diag);
      }
    }

    if (shouldReply) {
      await handleReply(issue, diag);
    }
    print('');
  }
}
