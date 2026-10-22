import 'dart:async';
import 'dart:convert';
import 'package:enough_mail/enough_mail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/email_parser.dart';

/// Represents a single fetched email candidate for transaction parsing.
class EmailMessageItem {
  EmailMessageItem({
    required this.id,
    required this.subject,
    required this.from,
    required this.date,
    required this.body,
    this.rawHtml,
    this.parsed,
    this.isAdded = false,
    this.isDismissed = false,
  });

  final String id;
  final String subject;
  final String from;
  final DateTime date;
  final String body;
  final String? rawHtml;
  final ParsedEmail? parsed;
  bool isAdded;
  bool isDismissed;

  String get previewSnippet {
    if (parsed != null) {
      return '${parsed!.isCredit ? "+" : "-"} ₹${parsed!.amount.toStringAsFixed(2)} · ${parsed!.merchant} · ${parsed!.paymentType}';
    }
    final clean = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 90 ? '${clean.substring(0, 90)}...' : clean;
  }
}

/// Abstract adapter for fetching emails over IMAP. Allows dependency injection for tests.
abstract class EmailClientAdapter {
  Future<void> connectAndLogin({
    required String email,
    required String appPassword,
  });

  Future<List<EmailMessageItem>> fetchRecentEmails({
    int messageCount = 50,
    int days = 14,
  });

  Future<void> disconnect();
}

/// Production implementation connecting to Gmail IMAP via [enough_mail].
class EnoughMailClientAdapter implements EmailClientAdapter {
  ImapClient? _client;

  @override
  Future<void> connectAndLogin({
    required String email,
    required String appPassword,
  }) async {
    final client = ImapClient(isLogEnabled: false);
    await client.connectToServer('imap.gmail.com', 993, isSecure: true);
    await client.login(email.trim(), appPassword.trim());
    _client = client;
  }

  @override
  Future<List<EmailMessageItem>> fetchRecentEmails({
    int messageCount = 50,
    int days = 14,
  }) async {
    final client = _client;
    if (client == null) {
      throw StateError('EmailClient is not connected. Call connectAndLogin first.');
    }

    await client.selectInbox();
    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    final afterStr =
        '${cutoffDate.year}/${cutoffDate.month.toString().padLeft(2, '0')}/${cutoffDate.day.toString().padLeft(2, '0')}';
    const keywords =
        '(spent OR debited OR credited OR received OR txn OR transaction OR alert OR inr OR rs OR "credit card" OR "debit card" OR purchase OR hdfc OR icici OR sbi OR axis OR kotak OR "yes bank" OR indusind)';

    SearchImapResult? searchResult;
    try {
      searchResult = await client.searchMessages(
        searchCriteria: 'X-GM-RAW "after:$afterStr $keywords"',
      );
    } catch (_) {
      try {
        final imapDate = DateCodec.encodeSearchDate(cutoffDate);
        searchResult = await client.searchMessages(
          searchCriteria: 'SINCE "$imapDate"',
        );
      } catch (_) {}
    }

    List<MimeMessage> messages = <MimeMessage>[];

    final seq = searchResult?.matchingSequence;
    if (seq != null && seq.isNotEmpty) {
      final cappedSeq = _capSequence(seq, maxCount: 150);
      final fetchResult = await client.fetchMessages(
        cappedSeq,
        '(FLAGS BODY[])',
      );
      messages = fetchResult.messages.reversed.toList();
    } else if (searchResult == null) {
      // Fallback: If server search failed or threw, fall back to recent messages
      final fetchResult = await client.fetchRecentMessages(
        messageCount: messageCount,
        criteria: '(FLAGS BODY[])',
      );
      messages = fetchResult.messages.reversed.toList();
    }

    final List<EmailMessageItem> results = <EmailMessageItem>[];

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final date = msg.decodeDate() ?? DateTime.now();
      if (date.isBefore(cutoffDate)) continue;

      final subject = msg.decodeSubject() ?? '';
      final from = msg.fromEmail ?? '';
      final plain = msg.decodeTextPlainPart();
      final html = msg.decodeTextHtmlPart();
      final body = (plain != null && plain.trim().isNotEmpty)
          ? plain.trim()
          : (html != null ? EmailParser.stripHtml(html) : '');

      if (body.isEmpty && subject.isEmpty) continue;

      // Smart bank / transaction keyword check
      if (!_matchesBankKeywords(subject, from, body)) continue;

      final parsed = EmailParser.parse(body.isNotEmpty ? body : subject, fallbackDate: date);
      final id = msg.decodeHeaderValue('message-id') ?? 'msg_${date.millisecondsSinceEpoch}_$i';

      results.add(EmailMessageItem(
        id: id,
        subject: subject.isEmpty ? '(No Subject)' : subject,
        from: from,
        date: date,
        body: body,
        rawHtml: html,
        parsed: parsed,
      ));
    }

    return results;
  }

  static MessageSequence _capSequence(MessageSequence seq, {int maxCount = 150}) {
    try {
      final list = seq.toList();
      if (list.length <= maxCount) return seq;
      final trimmed = list.sublist(list.length - maxCount);
      return MessageSequence.fromIds(trimmed, isUid: seq.isUidSequence);
    } catch (_) {
      return seq;
    }
  }

  static bool _matchesBankKeywords(String subject, String from, String body) {
    final lower = '$subject $from $body'.toLowerCase();
    return lower.contains('spent') ||
        lower.contains('debited') ||
        lower.contains('credited') ||
        lower.contains('received') ||
        lower.contains('transaction') ||
        lower.contains('txn') ||
        lower.contains('alert') ||
        lower.contains('inr') ||
        lower.contains('rs.') ||
        lower.contains('₹') ||
        lower.contains('credit card') ||
        lower.contains('debit card') ||
        lower.contains('purchase') ||
        lower.contains('hdfc') ||
        lower.contains('icici') ||
        lower.contains('sbi') ||
        lower.contains('axis') ||
        lower.contains('kotak') ||
        lower.contains('yes bank') ||
        lower.contains('indusind');
  }

  @override
  Future<void> disconnect() async {
    try {
      if (_client?.isLoggedIn == true) {
        await _client?.logout();
      }
    } catch (_) {}
    try {
      await _client?.disconnect();
    } catch (_) {}
    _client = null;
  }
}

/// Represents a saved email account configuration.
class EmailAccount {
  const EmailAccount({
    required this.email,
    required this.appPassword,
  });

  final String email;
  final String appPassword;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'email': email,
        'appPassword': appPassword,
      };

  factory EmailAccount.fromJson(Map<String, dynamic> json) => EmailAccount(
        email: (json['email'] as String? ?? '').trim(),
        appPassword: (json['appPassword'] as String? ?? '').trim(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailAccount &&
          runtimeType == other.runtimeType &&
          email.toLowerCase() == other.email.toLowerCase();

  @override
  int get hashCode => email.toLowerCase().hashCode;
}

/// Service managing Gmail connection credentials and email retrieval for single or multiple accounts.
class EmailService {
  EmailService._();
  static final EmailService instance = EmailService._();

  static const String _kAccountsKey = 'email_sync.accounts_json';
  static const String _kActiveEmailKey = 'email_sync.active_account_email';
  static const String _kLegacyEmailKey = 'email_sync.gmail_address';
  static const String _kLegacyAppPasswordKey = 'email_sync.app_password';
  static const String _kDismissedIdsKey = 'email_sync.dismissed_ids';
  static const String _kLookbackDaysKey = 'email_sync.lookback_days';

  EmailClientAdapter? _clientAdapter;

  EmailClientAdapter get adapter => _clientAdapter ??= EnoughMailClientAdapter();

  void setAdapterForTesting(EmailClientAdapter? adapter) {
    _clientAdapter = adapter;
  }

  /// Returns all configured email accounts, performing automatic migration from legacy single-account keys if needed.
  Future<List<EmailAccount>> getAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kAccountsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((item) => EmailAccount.fromJson(item as Map<String, dynamic>))
              .where((acc) => acc.email.isNotEmpty && acc.appPassword.isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    // Check legacy single-account migration
    final legacyEmail = prefs.getString(_kLegacyEmailKey);
    final legacyPassword = prefs.getString(_kLegacyAppPasswordKey);
    if (legacyEmail != null &&
        legacyEmail.isNotEmpty &&
        legacyPassword != null &&
        legacyPassword.isNotEmpty) {
      final account = EmailAccount(
        email: legacyEmail.trim(),
        appPassword: legacyPassword.trim(),
      );
      final list = <EmailAccount>[account];
      await prefs.setString(
          _kAccountsKey, jsonEncode(list.map((e) => e.toJson()).toList()));
      await prefs.setString(_kActiveEmailKey, account.email);
      await prefs.remove(_kLegacyEmailKey);
      await prefs.remove(_kLegacyAppPasswordKey);
      return list;
    }

    return <EmailAccount>[];
  }

  /// Returns the email address of the currently active account.
  Future<String?> getActiveEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getString(_kActiveEmailKey);
    final accounts = await getAccounts();
    if (accounts.isEmpty) return null;
    if (active != null &&
        accounts.any((a) => a.email.toLowerCase() == active.toLowerCase())) {
      return active;
    }
    return accounts.first.email;
  }

  /// Sets the active account to the specified email.
  Future<void> setActiveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveEmailKey, email.trim());
  }

  /// Returns the currently active [EmailAccount] or null if no accounts exist.
  Future<EmailAccount?> getActiveAccount() async {
    final accounts = await getAccounts();
    if (accounts.isEmpty) return null;
    final activeEmail = await getActiveEmail();
    if (activeEmail == null) return accounts.first;
    try {
      return accounts.firstWhere(
          (a) => a.email.toLowerCase() == activeEmail.toLowerCase());
    } catch (_) {
      return accounts.first;
    }
  }

  /// Checks if at least one email account is configured.
  Future<bool> isConfigured() async {
    final accounts = await getAccounts();
    return accounts.isNotEmpty;
  }

  /// Saves or updates an email account, setting it as the active account.
  Future<void> saveAccount(String email, String appPassword) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await getAccounts();
    final cleanEmail = email.trim();
    final cleanPassword = appPassword.trim().replaceAll(' ', '');

    final index = accounts.indexWhere(
        (a) => a.email.toLowerCase() == cleanEmail.toLowerCase());
    final updated = List<EmailAccount>.from(accounts);
    final newAccount = EmailAccount(email: cleanEmail, appPassword: cleanPassword);
    if (index >= 0) {
      updated[index] = newAccount;
    } else {
      updated.add(newAccount);
    }

    await prefs.setString(
        _kAccountsKey, jsonEncode(updated.map((e) => e.toJson()).toList()));
    await setActiveEmail(cleanEmail);
  }

  /// Removes an email account. If the removed account was active, switches to the next available account.
  Future<void> removeAccount(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await getAccounts();
    final cleanEmail = email.trim().toLowerCase();
    final updated =
        accounts.where((a) => a.email.toLowerCase() != cleanEmail).toList();

    await prefs.setString(
        _kAccountsKey, jsonEncode(updated.map((e) => e.toJson()).toList()));

    final activeEmail = prefs.getString(_kActiveEmailKey);
    if (activeEmail?.toLowerCase() == cleanEmail) {
      if (updated.isNotEmpty) {
        await prefs.setString(_kActiveEmailKey, updated.first.email);
      } else {
        await prefs.remove(_kActiveEmailKey);
      }
    }
  }

  /// Backward-compatible getter for active email.
  Future<String?> getSavedEmail() async => (await getActiveAccount())?.email;

  /// Backward-compatible getter for active app password.
  Future<String?> getSavedAppPassword() async =>
      (await getActiveAccount())?.appPassword;

  /// Backward-compatible saver for credentials.
  Future<void> saveCredentials(String email, String appPassword) =>
      saveAccount(email, appPassword);

  /// Clears all saved email accounts and credentials.
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccountsKey);
    await prefs.remove(_kActiveEmailKey);
    await prefs.remove(_kLegacyEmailKey);
    await prefs.remove(_kLegacyAppPasswordKey);
  }

  Future<List<String>> getDismissedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kDismissedIdsKey) ?? <String>[];
  }

  Future<void> dismissEmail(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kDismissedIdsKey) ?? <String>[];
    if (!list.contains(id)) {
      list.add(id);
      await prefs.setStringList(_kDismissedIdsKey, list);
    }
  }

  /// Returns the saved lookback days preference (defaults to 14).
  Future<int> getSavedLookbackDays() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLookbackDaysKey) ?? 14;
  }

  /// Persists the user's selected lookback days preference (7, 14, 30).
  Future<void> saveLookbackDays(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLookbackDaysKey, days);
  }

  /// Fetches recent emails for the specified [accountEmail], or the active account if omitted.
  Future<List<EmailMessageItem>> fetchEmails({
    int days = 14,
    String? accountEmail,
  }) async {
    EmailAccount? targetAccount;
    if (accountEmail != null && accountEmail.isNotEmpty) {
      final accounts = await getAccounts();
      targetAccount = accounts.cast<EmailAccount?>().firstWhere(
            (a) => a?.email.toLowerCase() == accountEmail.toLowerCase(),
            orElse: () => null,
          );
    }
    targetAccount ??= await getActiveAccount();

    if (targetAccount == null ||
        targetAccount.email.isEmpty ||
        targetAccount.appPassword.isEmpty) {
      throw StateError(
          'Gmail is not configured. Please enter your Gmail address and App Password.');
    }

    await adapter.connectAndLogin(
      email: targetAccount.email,
      appPassword: targetAccount.appPassword,
    );
    try {
      final items = await adapter.fetchRecentEmails(days: days);
      final dismissed = await getDismissedIds();
      for (final item in items) {
        if (dismissed.contains(item.id)) {
          item.isDismissed = true;
        }
      }
      return items;
    } finally {
      await adapter.disconnect();
    }
  }
}
