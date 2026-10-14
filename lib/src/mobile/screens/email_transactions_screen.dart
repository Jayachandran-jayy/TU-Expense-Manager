import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/email_parser.dart';
import '../../core/models.dart';
import '../../core/parser.dart';
import '../services/email_service.dart';
import '../services/local_llm_service.dart';
import 'add_transaction_screen.dart';

/// Screen for managing email transactions: paste raw email text or fetch from Gmail IMAP,
/// preview parsed transaction data, and verify before saving to the ledger.
class EmailTransactionsScreen extends StatefulWidget {
  const EmailTransactionsScreen({
    super.key,
    required this.categories,
    required this.merchants,
    required this.paymentTypes,
    required this.transactions,
    required this.onChanged,
    this.aiParserOverride,
    this.aiModelAvailableOverride,
  });

  final List<ExpenseCategory> categories;
  final List<String> merchants;
  final List<String> paymentTypes;
  final List<ExpenseTxn> transactions;
  final Future<void> Function() onChanged;
  final Future<ParsedSms?> Function(String text, {DateTime? receivedAt})?
      aiParserOverride;
  final bool? aiModelAvailableOverride;

  @override
  State<EmailTransactionsScreen> createState() => _EmailTransactionsScreenState();
}

class _EmailTransactionsScreenState extends State<EmailTransactionsScreen> {
  final EmailService _emailService = EmailService.instance;
  final DateFormat _dateFormat = DateFormat('d MMM yyyy, h:mm a');

  bool _isConfigured = false;
  String? _connectedEmail;
  List<EmailAccount> _accounts = <EmailAccount>[];
  bool _loading = false;
  String? _errorMessage;
  int _selectedDays = 14;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<EmailMessageItem> _emails = <EmailMessageItem>[];
  final Set<String> _addedEmailIds = <String>{};

  @override
  void initState() {
    super.initState();
    _checkStatusAndLoad();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkStatusAndLoad() async {
    final accounts = await _emailService.getAccounts();
    final activeEmail = await _emailService.getActiveEmail();
    final configured = accounts.isNotEmpty;
    if (!mounted) return;

    setState(() {
      _accounts = accounts;
      _isConfigured = configured;
      _connectedEmail = activeEmail;
    });

    if (configured) {
      await _fetchEmails();
    }
  }

  Future<void> _fetchEmails() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final items = await _emailService.fetchEmails(
        days: _selectedDays,
        accountEmail: _connectedEmail,
      );
      _markAlreadyAdded(items);

      if (!mounted) return;
      setState(() {
        _emails = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  /// Cross-references emails with active ledger transactions to mark already added ones.
  void _markAlreadyAdded(List<EmailMessageItem> items) {
    for (final item in items) {
      if (_addedEmailIds.contains(item.id)) {
        item.isAdded = true;
        continue;
      }
      final parsed = item.parsed;
      if (parsed != null) {
        final amt = parsed.amount;
        final pDate = parsed.date;
        final pMerchant = parsed.merchant.toLowerCase();
        final pPayment = parsed.paymentType.toLowerCase();

        final matches = widget.transactions.any((t) =>
            (t.amount - amt).abs() < 0.01 &&
            (t.date.year == pDate.year &&
                t.date.month == pDate.month &&
                t.date.day == pDate.day) &&
            (t.merchant.toLowerCase() == pMerchant ||
                t.paymentType.toLowerCase() == pPayment));
        if (matches) {
          item.isAdded = true;
        }
      }
    }
  }

  Future<void> _connectGmailDialog({String? initialEmail}) async {
    final emailCtrl = TextEditingController(
      text: initialEmail ?? (_accounts.isEmpty ? (_connectedEmail ?? '') : ''),
    );
    final passCtrl = TextEditingController();
    bool obscurePass = true;
    bool saving = false;
    String? dialogError;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(Icons.mail_outline),
              SizedBox(width: 8),
              Text('Connect Gmail'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Connect using your Gmail address and a 16-character Google App Password.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Gmail Address',
                    hintText: 'e.g. user@gmail.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: obscurePass,
                  decoration: InputDecoration(
                    labelText: 'App Password',
                    hintText: '16-character password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePass ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'How to create: Go to myaccount.google.com/apppasswords with 2-Step Verification enabled, generate an App Password for "Mail", and paste it here.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                if (dialogError != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    dialogError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      final pass = passCtrl.text.trim();
                      if (email.isEmpty || pass.isEmpty) {
                        setDialogState(() => dialogError = 'Please enter both email and App Password.');
                        return;
                      }

                      setDialogState(() {
                        saving = true;
                        dialogError = null;
                      });

                      try {
                        // Test authentication
                        await _emailService.adapter.connectAndLogin(
                          email: email,
                          appPassword: pass,
                        );
                        await _emailService.adapter.disconnect();

                        await _emailService.saveAccount(email, pass);
                        if (!dialogCtx.mounted) return;
                        Navigator.pop(dialogCtx);

                        await _checkStatusAndLoad();
                      } catch (e) {
                        setDialogState(() {
                          saving = false;
                          dialogError = 'Connection failed: ${e.toString().replaceFirst("Exception: ", "")}';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAccountSwitcherSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text(
                      'Gmail Accounts',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Account', style: TextStyle(fontSize: 12)),
                      onPressed: () {
                        Navigator.pop(sheetCtx);
                        _connectGmailDialog();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _accounts.length,
                  itemBuilder: (ctx, i) {
                    final acc = _accounts[i];
                    final isActive =
                        acc.email.toLowerCase() == _connectedEmail?.toLowerCase();
                    return ListTile(
                      leading: Icon(
                        isActive ? Icons.check_circle : Icons.mail_outline,
                        color: isActive
                            ? Colors.green
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        acc.email,
                        style: TextStyle(
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: isActive
                          ? const Text(
                              'Active account',
                              style: TextStyle(color: Colors.green, fontSize: 11),
                            )
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'Remove account',
                        onPressed: () =>
                            _confirmRemoveAccount(sheetCtx, acc.email),
                      ),
                      onTap: () async {
                        if (!isActive) {
                          await _emailService.setActiveEmail(acc.email);
                          if (!mounted) return;
                          setState(() {
                            _connectedEmail = acc.email;
                          });
                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx);
                          }
                          await _fetchEmails();
                        } else {
                          if (sheetCtx.mounted) {
                            Navigator.pop(sheetCtx);
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemoveAccount(BuildContext sheetCtx, String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $email?'),
        content: const Text(
          'This will remove this email account from the device. You can reconnect it at any time.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await _emailService.removeAccount(email);
    if (!mounted) return;
    if (sheetCtx.mounted) {
      Navigator.pop(sheetCtx);
    }
    await _checkStatusAndLoad();
  }

  Future<void> _disconnectGmail() async {
    final email = _connectedEmail;
    final isMulti = _accounts.length > 1;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isMulti && email != null
            ? 'Disconnect $email?'
            : 'Disconnect Gmail?'),
        content: Text(
          isMulti
              ? 'This account will be removed from this device.'
              : 'Your saved credentials will be cleared from this device. You can connect again at any time.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (isMulti && email != null) {
      await _emailService.removeAccount(email);
    } else {
      await _emailService.clearCredentials();
    }
    await _checkStatusAndLoad();
  }

  Future<void> _pasteEmailDialog() async {
    final textController = TextEditingController();
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste Email Alert'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                'Paste the bank transaction email text or HTML below. The parser will extract transaction fields and open verification.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: textController,
                maxLines: 8,
                minLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Thank you for using your HDFC Bank Credit Card ending in 1234 for INR 1,500.00 at AMAZON...',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, textController.text),
            child: const Text('Parse & Verify'),
          ),
        ],
      ),
    );

    if (body == null || body.trim().isEmpty) return;
    await _openVerification(body);
  }

  Future<void> _openVerification(String emailContent, [EmailMessageItem? item]) async {
    final fallbackDate = item?.date ?? DateTime.now();
    ParsedEmail? parsed = item?.parsed ??
        EmailParser.parse(emailContent, fallbackDate: fallbackDate);

    // Smart Local LLM fallback: if regex could not parse a valid transaction or amount <= 0,
    // invoke the on-device AI model if available.
    if (parsed == null || parsed.amount <= 0) {
      final bool aiAvailable = widget.aiModelAvailableOverride ??
          await LocalLlmService.instance.isModelAvailable();
      if (aiAvailable) {
        if (mounted) {
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => const AlertDialog(
              content: Row(
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Expanded(child: Text('Parsing with local AI...')),
                ],
              ),
            ),
          );
        }

        ParsedSms? aiParsed;
        try {
          final parser =
              widget.aiParserOverride ?? LocalLlmService.instance.parseEmail;
          aiParsed = await parser(emailContent, receivedAt: fallbackDate);
        } catch (_) {}

        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }

        if (aiParsed != null && aiParsed.amount > 0) {
          parsed = ParsedEmail(
            amount: aiParsed.amount,
            merchant: aiParsed.merchant,
            paymentType: aiParsed.paymentType,
            date: aiParsed.date,
            direction: aiParsed.direction,
            reference: aiParsed.reference,
            bank: 'ai-llm-local',
          );
        }
      }
    }

    final resolvedParsed = parsed ??
        ParsedEmail(
          amount: EmailParser.extractAmountOnly(emailContent) ?? 0.0,
          paymentType:
              EmailParser.extractInstrumentOnly(emailContent) ?? 'Credit Card',
          merchant: EmailParser.extractMerchantOnly(emailContent) ?? '',
          date: EmailParser.extractDateOnly(emailContent,
                      fallbackDate: fallbackDate)
                  ?.date ??
              fallbackDate,
          direction: TxnDirection.debit,
        );

    final txnDate = (resolvedParsed.hasExplicitTime || item == null)
        ? resolvedParsed.date
        : DateTime(
            resolvedParsed.date.year,
            resolvedParsed.date.month,
            resolvedParsed.date.day,
            item.date.hour,
            item.date.minute,
            item.date.second,
          );

    if (!mounted) return;
    final bool? added = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => AddTransactionScreen(
          categories: widget.categories,
          merchants: widget.merchants,
          paymentTypes: widget.paymentTypes,
          initialAmount:
              resolvedParsed.amount > 0 ? resolvedParsed.amount : null,
          initialMerchant: resolvedParsed.merchant.isNotEmpty
              ? resolvedParsed.merchant
              : null,
          initialPaymentType: resolvedParsed.paymentType.isNotEmpty
              ? resolvedParsed.paymentType
              : null,
          initialDate: txnDate,
          initialNotes: resolvedParsed.reference.isNotEmpty
              ? 'Ref: ${resolvedParsed.reference}'
              : null,
          initialDirection: resolvedParsed.direction,
        ),
      ),
    );

    if (added == true) {
      if (item != null) {
        setState(() {
          item.isAdded = true;
          _addedEmailIds.add(item.id);
        });
      }
      await widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            resolvedParsed.merchant.isNotEmpty
                ? 'Transaction added for ${resolvedParsed.merchant}'
                : 'Transaction added from email',
          ),
        ),
      );
    }
  }

  Future<void> _dismissEmail(EmailMessageItem item) async {
    await _emailService.dismissEmail(item.id);
    setState(() {
      item.isDismissed = true;
    });
  }

  List<EmailMessageItem> get _filteredEmails {
    final query = _searchQuery.trim().toLowerCase();
    return _emails.where((item) {
      if (item.isDismissed) return false;
      if (query.isEmpty) return true;
      return item.subject.toLowerCase().contains(query) ||
          item.from.toLowerCase().contains(query) ||
          item.body.toLowerCase().contains(query) ||
          (item.parsed != null && item.parsed!.merchant.toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredEmails;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Transactions'),
        actions: <Widget>[
          if (_isConfigured)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh emails',
              onPressed: _loading ? null : _fetchEmails,
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 1. Top Hub Bar: Quick Paste Email & Status Card
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: <Widget>[
                // Quick Paste Action Card
                Card(
                  elevation: 0,
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.content_paste_outlined, color: colorScheme.primary),
                    title: const Text('Paste Email Text', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Copy & paste directly from your email app without connecting Gmail'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: _pasteEmailDialog,
                  ),
                ),
                const SizedBox(height: 8),

                // Gmail Connection Status Card
                Card(
                  elevation: 0,
                  color: _isConfigured
                      ? colorScheme.primaryContainer.withValues(alpha: 0.2)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: _isConfigured
                          ? colorScheme.primary.withValues(alpha: 0.5)
                          : colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _isConfigured
                                ? Colors.green.withValues(alpha: 0.15)
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.mail_outline,
                            color: _isConfigured ? Colors.green : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              if (_isConfigured)
                                InkWell(
                                  onTap: _showAccountSwitcherSheet,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      Flexible(
                                        child: Text(
                                          'Connected: $_connectedEmail',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(Icons.arrow_drop_down, size: 18),
                                    ],
                                  ),
                                )
                              else
                                const Text(
                                  'Gmail Not Connected',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              Text(
                                _isConfigured
                                    ? (_accounts.length > 1
                                        ? '${_accounts.length} accounts connected · Tap to switch'
                                        : 'Tap to switch account or add secondary email')
                                    : 'Connect using an App Password to list emails',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_isConfigured) ...<Widget>[
                          if (_accounts.length > 1)
                            IconButton(
                              icon: const Icon(Icons.switch_account_outlined, size: 20),
                              tooltip: 'Switch account',
                              onPressed: _showAccountSwitcherSheet,
                            ),
                          TextButton(
                            onPressed: _disconnectGmail,
                            child: const Text('Disconnect', style: TextStyle(fontSize: 12)),
                          ),
                        ] else
                          FilledButton.tonal(
                            onPressed: _connectGmailDialog,
                            child: const Text('Connect', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Filter Bar: Days Chips + Search Bar (Only when configured)
          if (_isConfigured) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: <Widget>[
                  Text(
                    'Lookback:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  for (final days in const <int>[7, 14, 30])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('$days days', style: const TextStyle(fontSize: 11)),
                        selected: _selectedDays == days,
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _selectedDays = days);
                            _fetchEmails();
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search subjects, merchants, or senders...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),
          ],

          const Divider(height: 1),

          // 3. Email List
          Expanded(
            child: _buildListContent(filtered, colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildListContent(List<EmailMessageItem> items, ColorScheme colorScheme) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Fetching transaction emails from Gmail...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 44, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Could not load emails',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _fetchEmails,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isConfigured) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.mark_email_unread_outlined, size: 54, color: colorScheme.primary.withValues(alpha: 0.6)),
              const SizedBox(height: 16),
              const Text(
                'Connect your Gmail or Paste Email Text',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'You can tap "Paste Email Text" above to paste any bank transaction email, or connect Gmail with an App Password to browse recent alerts.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.inbox_outlined, size: 48, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text(
                'No bank transaction emails found',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                _searchQuery.isNotEmpty
                    ? 'No emails match "$_searchQuery".'
                    : 'No transaction alerts found in the last $_selectedDays days.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final item = items[idx];
        final parsed = item.parsed;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: item.isAdded
                  ? Colors.green.withValues(alpha: 0.4)
                  : colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openVerification(item.body.isNotEmpty ? item.body : item.subject, item),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Header: Sender & Date + Added Badge
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.from.isNotEmpty ? item.from : 'Bank Notification',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (item.isAdded)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(Icons.check_circle, size: 12, color: Colors.green),
                              SizedBox(width: 4),
                              Text('Added', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Dismiss email',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => _dismissEmail(item),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Subject
                  Text(
                    item.subject,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 6),

                  // Parsed Preview Snippet or Raw Text
                  if (parsed != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            parsed.isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                            size: 14,
                            color: parsed.isCredit ? Colors.green : colorScheme.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '₹${parsed.amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: parsed.isCredit ? Colors.green : colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${parsed.merchant} · ${parsed.paymentType}',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Text(
                      item.previewSnippet,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),

                  const SizedBox(height: 6),
                  // Timestamp
                  Text(
                    _dateFormat.format(item.date),
                    style: TextStyle(fontSize: 11, color: colorScheme.outline),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
