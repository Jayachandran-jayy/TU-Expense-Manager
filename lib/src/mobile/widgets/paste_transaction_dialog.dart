/// Unified paste dialog for adding transactions from bank SMS or email text.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/email_parser.dart';
import '../../core/models.dart';
import '../../core/parser.dart';
import '../database.dart';
import '../screens/add_transaction_screen.dart';
import '../services/local_llm_service.dart';

/// Shows the unified paste dialog to parse raw SMS or email text into a transaction.
Future<void> showPasteTransactionDialog(
  BuildContext context, {
  List<ExpenseCategory>? categories,
  List<String>? merchants,
  List<String>? paymentTypes,
  AppDatabase? database,
  VoidCallback? onTransactionAdded,
}) async {
  final AppDatabase db = database ?? AppDatabase.instance;
  final List<ExpenseCategory> cats =
      categories ?? await db.categories();
  final List<String> pTypes =
      paymentTypes ?? await db.paymentMethods();
  final List<String> merchs = merchants ??
      (await db.transactions()).map((t) => t.merchant).toSet().toList()
        ..sort();

  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => PasteTransactionDialog(
      categories: cats,
      merchants: merchs,
      paymentTypes: pTypes,
      onTransactionAdded: onTransactionAdded,
    ),
  );
}

/// A dialog allowing users to paste SMS or email transaction text and extract details.
class PasteTransactionDialog extends StatefulWidget {
  const PasteTransactionDialog({
    super.key,
    required this.categories,
    required this.merchants,
    required this.paymentTypes,
    this.onTransactionAdded,
  });

  final List<ExpenseCategory> categories;
  final List<String> merchants;
  final List<String> paymentTypes;
  final VoidCallback? onTransactionAdded;

  @override
  State<PasteTransactionDialog> createState() => _PasteTransactionDialogState();
}

class _PasteTransactionDialogState extends State<PasteTransactionDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isParsing = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      setState(() {
        _controller.text = data.text!.trim();
        _errorMessage = null;
      });
    }
  }

  Future<void> _parseAndProceed() async {
    final String raw = _controller.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorMessage = 'Please paste SMS or email text first.');
      return;
    }

    setState(() {
      _isParsing = true;
      _errorMessage = null;
    });

    ParsedSms? parsed;

    // 1. Try SMS regex
    parsed = SmsParser.parse(raw);

    // 2. Try Email regex
    if (parsed == null) {
      final ParsedEmail? emailParsed = EmailParser.parse(raw);
      if (emailParsed != null) {
        parsed = emailParsed.toParsedSms();
      }
    }

    // 3. Try on-device AI fallback
    if (parsed == null) {
      final bool aiAvailable =
          await LocalLlmService.instance.isModelAvailable();
      if (aiAvailable) {
        try {
          parsed = await LocalLlmService.instance.parseSms(raw);
        } catch (_) {
          // AI parse failed, fallback handled below
        }
      }
    }

    if (!mounted) return;

    if (parsed != null) {
      Navigator.of(context).pop(); // Dismiss paste dialog

      final bool? added = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => AddTransactionScreen(
            categories: widget.categories,
            merchants: widget.merchants,
            paymentTypes: widget.paymentTypes,
            initialSmsBody: raw,
            initialAmount: parsed!.amount,
            initialMerchant: parsed.merchant,
            initialPaymentType: parsed.paymentType,
            initialDate: parsed.date,
            initialDirection: parsed.direction,
            initialNotes: parsed.reference.isNotEmpty
                ? 'Ref: ${parsed.reference}'
                : null,
          ),
        ),
      );

      if (added == true) {
        widget.onTransactionAdded?.call();
      }
    } else {
      setState(() {
        _isParsing = false;
        _errorMessage =
            'Could not extract transaction details. Make sure the text includes an amount and merchant, or that on-device AI is downloaded.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.content_paste_outlined, color: colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Paste transaction')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste any bank SMS alert or transaction email to extract details automatically.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 3,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Sent Rs.90.00 from A/c *4668 to M/S.SHOP...\nor HDFC Bank email alert...',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  tooltip: 'Paste from clipboard',
                  onPressed: _pasteFromClipboard,
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (_isParsing) ...[
              const SizedBox(height: 16),
              const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Parsing with AI / regex...'),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isParsing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Parse'),
          onPressed: _isParsing ? null : _parseAndProceed,
        ),
      ],
    );
  }
}
