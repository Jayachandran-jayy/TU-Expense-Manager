import 'dart:async';
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
    final fetchResult = await client.fetchRecentMessages(
      messageCount: messageCount,
      criteria: '(FLAGS BODY[])',
    );

    final List<EmailMessageItem> results = <EmailMessageItem>[];
    final cutoffDate = DateTime.now().subtract(Duration(days: days));

    // Sort newest messages first
    final messages = fetchResult.messages.reversed.toList();

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

  static bool _matchesBankKeywords(String subject, String from, String body) {
    final lower = '$subject $from $body'.toLowerCase();
    return lower.contains('spent') ||
        lower.contains('debited') ||
        lower.contains('transaction') ||
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

/// Service managing Gmail connection credentials and email retrieval.
class EmailService {
  EmailService._();
  static final EmailService instance = EmailService._();

  static const String _kEmailKey = 'email_sync.gmail_address';
  static const String _kAppPasswordKey = 'email_sync.app_password';
  static const String _kDismissedIdsKey = 'email_sync.dismissed_ids';

  EmailClientAdapter? _clientAdapter;

  EmailClientAdapter get adapter => _clientAdapter ??= EnoughMailClientAdapter();

  void setAdapterForTesting(EmailClientAdapter? adapter) {
    _clientAdapter = adapter;
  }

  Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kEmailKey);
  }

  Future<String?> getSavedAppPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAppPasswordKey);
  }

  Future<bool> isConfigured() async {
    final email = await getSavedEmail();
    final password = await getSavedAppPassword();
    return email != null && email.isNotEmpty && password != null && password.isNotEmpty;
  }

  Future<void> saveCredentials(String email, String appPassword) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmailKey, email.trim());
    await prefs.setString(_kAppPasswordKey, appPassword.trim().replaceAll(' ', ''));
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmailKey);
    await prefs.remove(_kAppPasswordKey);
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

  Future<List<EmailMessageItem>> fetchEmails({int days = 14}) async {
    final email = await getSavedEmail();
    final password = await getSavedAppPassword();
    if (email == null || password == null || email.isEmpty || password.isEmpty) {
      throw StateError('Gmail is not configured. Please enter your Gmail address and App Password.');
    }

    await adapter.connectAndLogin(email: email, appPassword: password);
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
