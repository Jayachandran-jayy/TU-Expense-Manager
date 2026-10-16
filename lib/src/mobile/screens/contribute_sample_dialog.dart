/// Interactive modal dialog for voluntarily contributing sanitized bank SMS formats.
///
/// Features a simple 3-step guide, automatic PII redaction preview, direct GitHub issue
/// launching, and clickable link to the GitHub README guide.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/pii_sanitizer.dart';
import '../services/github_contribution_helper.dart';

class ContributeSampleDialog extends StatefulWidget {
  const ContributeSampleDialog({
    super.key,
    required this.rawSms,
    this.initialBank,
    this.initialMerchant,
    this.initialAmount,
    this.initialDirection = 'Debit',
    this.initialDate,
  });

  final String rawSms;
  final String? initialBank;
  final String? initialMerchant;
  final double? initialAmount;
  final String initialDirection;
  final String? initialDate;

  /// Shows the dialog as a responsive bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String rawSms,
    String? initialBank,
    String? initialMerchant,
    double? initialAmount,
    String initialDirection = 'Debit',
    String? initialDate,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ContributeSampleDialog(
        rawSms: rawSms,
        initialBank: initialBank,
        initialMerchant: initialMerchant,
        initialAmount: initialAmount,
        initialDirection: initialDirection,
        initialDate: initialDate,
      ),
    );
  }

  @override
  State<ContributeSampleDialog> createState() => _ContributeSampleDialogState();
}

class _ContributeSampleDialogState extends State<ContributeSampleDialog> {
  late final TextEditingController _smsController;
  late final TextEditingController _bankController;
  late final TextEditingController _merchantController;
  late final TextEditingController _amountController;
  late String _direction;
  late final SanitizedResult _sanitizedResult;

  @override
  void initState() {
    super.initState();
    _sanitizedResult = PiiSanitizer.instance.sanitize(widget.rawSms);
    _smsController = TextEditingController(text: _sanitizedResult.sanitizedText);
    _bankController = TextEditingController(text: widget.initialBank ?? _detectBank(widget.rawSms));
    _merchantController = TextEditingController(text: widget.initialMerchant ?? '');
    _amountController = TextEditingController(
      text: widget.initialAmount != null ? widget.initialAmount!.toStringAsFixed(2) : '',
    );
    _direction = widget.initialDirection;
  }

  @override
  void dispose() {
    _smsController.dispose();
    _bankController.dispose();
    _merchantController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  String _detectBank(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('hdfc')) return 'HDFC Bank';
    if (lower.contains('sbi') || lower.contains('state bank')) return 'SBI';
    if (lower.contains('icici')) return 'ICICI Bank';
    if (lower.contains('axis')) return 'Axis Bank';
    if (lower.contains('kotak')) return 'Kotak Bank';
    if (lower.contains('pnb') || lower.contains('punjab national')) return 'PNB';
    if (lower.contains('canara')) return 'Canara Bank';
    if (lower.contains('indian bank')) return 'Indian Bank';
    if (lower.contains('bob') || lower.contains('baroda')) return 'Bank of Baroda';
    if (lower.contains('yes bank')) return 'YES Bank';
    if (lower.contains('federal bank')) return 'Federal Bank';
    if (lower.contains('idfc')) return 'IDFC FIRST Bank';
    return '';
  }

  Future<void> _submitToGitHub() async {
    final amount = double.tryParse(_amountController.text.trim().replaceAll(',', ''));
    final merchant = _merchantController.text.trim().isEmpty ? 'Unknown' : _merchantController.text.trim();
    final bank = _bankController.text.trim();

    await GitHubContributionHelper.launchContributionFlow(
      sanitizedSms: _smsController.text.trim(),
      bankHint: bank,
      transactionType: _direction,
      amount: amount,
      merchant: merchant,
      date: widget.initialDate,
    );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sanitized data copied to clipboard and GitHub opened! Tap "Submit new issue" on GitHub.'),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _copyJson() {
    final amount = double.tryParse(_amountController.text.trim().replaceAll(',', ''));
    final merchant = _merchantController.text.trim().isEmpty ? 'Unknown' : _merchantController.text.trim();
    final bank = _bankController.text.trim();

    final payload = <String, dynamic>{
      'bank': bank,
      'type': _direction.toLowerCase(),
      'amount': amount,
      'merchant': merchant,
      'sanitized_sms': _smsController.text.trim(),
    };

    Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(payload)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sanitized JSON copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16181D) : theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Title & Icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.volunteer_activism_rounded, color: colorScheme.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Contribute SMS Format',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Help train local AI & expand code-baked RAG',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3-Step Guide Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E222B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.primary.withAlpha(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Simple 3-Step Contribution Guide',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildStepRow('1', 'Inspect Redactions', 'Account numbers, balances, & refs are masked.'),
                  const SizedBox(height: 4),
                  _buildStepRow('2', '1-Tap Submit', 'Copies data and opens a pre-filled GitHub issue.'),
                  const SizedBox(height: 4),
                  _buildStepRow('3', 'Submit on GitHub', 'Click "Submit new issue" on GitHub to share!'),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: GitHubContributionHelper.openReadmeGuide,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.open_in_new_rounded, size: 14, color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Read our Simple Contribution Guide on GitHub ↗',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.primary,
                                decoration: TextDecoration.underline,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Masked Entities Chips
            if (_sanitizedResult.hasRedactions) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _sanitizedResult.detectedEntities.map((e) {
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: Colors.green.withAlpha(30),
                    side: BorderSide(color: Colors.green.withAlpha(80)),
                    label: Text(
                      '🔒 $e Masked',
                      style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
            ],

            // Sanitized SMS Text Field
            TextField(
              controller: _smsController,
              maxLines: 3,
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: 'Sanitized SMS (Verify No Personal Details)',
                labelStyle: const TextStyle(fontSize: 12),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Bank Name & Amount Fields
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bankController,
                    decoration: InputDecoration(
                      labelText: 'Bank / Issuer',
                      hintText: 'e.g. HDFC Bank, SBI',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (₹)',
                      hintText: 'e.g. 450.00',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Direction & Merchant Row
            Row(
              children: [
                // Direction Segmented Toggle
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildDirectionButton('Debit'),
                      _buildDirectionButton('Credit'),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _merchantController,
                    decoration: InputDecoration(
                      labelText: 'Merchant',
                      hintText: 'e.g. Swiggy, Amazon',
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Action Buttons
            FilledButton.icon(
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Contribute on GitHub ↗'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _submitToGitHub,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Sanitized JSON'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _copyJson,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(String num, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            num,
            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12),
              children: [
                TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDirectionButton(String dir) {
    final selected = _direction == dir;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: () => setState(() => _direction = dir),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          dir,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: selected ? Colors.white : theme.textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }
}
