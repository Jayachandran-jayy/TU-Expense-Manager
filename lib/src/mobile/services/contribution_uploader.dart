/// Sends one reviewed SMS sample to the anonymous contributions table.
///
/// Nothing leaves the device unless the user has opted in. The request carries
/// only the fields in [SmsContribution.toJson]: no account, device or GitHub identifiers.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../../core/ledger_prefs.dart';
import '../../core/pii_sanitizer.dart';

/// The outcome of one send. Only [sent] means the row reached the server.
enum ContributionResult { sent, disabled, notConfigured, hasPersonalDetails, tooLong, offline, rejected }

/// One reviewed sample. Every field here is shown to the user before sending.
class SmsContribution {
  const SmsContribution({
    required this.bank,
    required this.txnType,
    required this.amount,
    required this.merchant,
    required this.sanitizedSms,
  });

  final String bank;
  final String txnType;
  final double? amount;
  final String merchant;
  final String sanitizedSms;

  Map<String, Object?> toJson() => <String, Object?>{
        'bank': bank,
        'txn_type': txnType,
        'amount': amount,
        'merchant': merchant,
        'sanitized_sms': sanitizedSms,
      };
}

class ContributionUploader {
  ContributionUploader({
    http.Client? client,
    LedgerPrefs? prefs,
    String? baseUrl,
    String? anonKey,
  })  : _client = client ?? http.Client(),
        _prefs = prefs ?? LedgerPrefs.instance,
        _baseUrl = baseUrl ?? kContributionUrl,
        _anonKey = anonKey ?? kContributionKey;

  /// Matches the `sanitized_sms` length check in `server/contrib/schema.sql`.
  static const int maxSmsLength = 1000;

  static const Duration timeout = Duration(seconds: 15);

  final http.Client _client;
  final LedgerPrefs _prefs;
  final String _baseUrl;
  final String _anonKey;

  /// Sends [sample] if the user has opted in and the text passes a final check.
  Future<ContributionResult> send(SmsContribution sample) async {
    if (_baseUrl.isEmpty || _anonKey.isEmpty) return ContributionResult.notConfigured;
    if (!await _prefs.contributeEnabled()) return ContributionResult.disabled;

    // Re-check at send time, so text edited by hand cannot carry personal details out.
    if (PiiSanitizer.instance.sanitize(sample.sanitizedSms).hasRedactions) {
      return ContributionResult.hasPersonalDetails;
    }
    if (sample.sanitizedSms.length > maxSmsLength) return ContributionResult.tooLong;

    final Uri uri = Uri.parse('$_baseUrl/rest/v1/sms_contributions');
    try {
      final http.Response response = await _client
          .post(
            uri,
            headers: <String, String>{
              'apikey': _anonKey,
              'Authorization': 'Bearer $_anonKey',
              'Content-Type': 'application/json',
              'Prefer': 'return=minimal',
            },
            body: jsonEncode(sample.toJson()),
          )
          .timeout(timeout);
      final bool ok = response.statusCode >= 200 && response.statusCode < 300;
      return ok ? ContributionResult.sent : ContributionResult.rejected;
    } on TimeoutException {
      return ContributionResult.offline;
    } on http.ClientException {
      return ContributionResult.offline;
    }
  }

  void close() => _client.close();
}
