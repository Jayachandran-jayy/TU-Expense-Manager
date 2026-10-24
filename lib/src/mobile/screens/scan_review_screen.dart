/// Screen allowing users to review and selectively add candidate transactions
/// discovered during SMS inbox and unadded SMS scans.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/parser.dart';
import '../../ui_shared/formats.dart';
import '../database.dart';

/// A candidate transaction extracted during an SMS scan awaiting user review.
class CandidateTransaction {
  CandidateTransaction({
    required this.parsed,
    this.rawBody = '',
    this.unaddedSmsId,
    this.selected = true,
  });

  final ParsedSms parsed;
  final String rawBody;
  final int? unaddedSmsId;
  bool selected;
}

/// Screen presenting scanned candidate transactions with batch selection.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.candidates,
    this.database,
    this.onAdded,
    this.onShare,
  });

  final List<CandidateTransaction> candidates;
  final AppDatabase? database;
  final VoidCallback? onAdded;

  /// Shows a "share this format" action when set (statement imports only).
  final VoidCallback? onShare;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  late final List<CandidateTransaction> _candidates =
      List<CandidateTransaction>.from(widget.candidates);

  final NumberFormat _money = appMoneyFormat();
  final DateFormat _dateFormat = DateFormat('d MMM yyyy, h:mm a');
  final DateFormat _dateOnlyFormat = DateFormat('d MMM yyyy');
  bool _isSaving = false;

  AppDatabase get _db => widget.database ?? AppDatabase.instance;

  int get _selectedCount =>
      _candidates.where((CandidateTransaction c) => c.selected).length;

  double get _selectedTotal => _candidates
      .where((CandidateTransaction c) => c.selected)
      .fold<double>(0, (double sum, CandidateTransaction c) => sum + c.parsed.amount);

  bool get _allSelected =>
      _candidates.isNotEmpty && _candidates.every((CandidateTransaction c) => c.selected);

  void _toggleSelectAll() {
    final bool target = !_allSelected;
    setState(() {
      for (final CandidateTransaction c in _candidates) {
        c.selected = target;
      }
    });
  }

  Future<void> _addSelected() async {
    final List<CandidateTransaction> selected =
        _candidates.where((CandidateTransaction c) => c.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _isSaving = true);

    int addedCount = 0;
    for (final CandidateTransaction candidate in selected) {
      final int id = await _db.insertParsed(candidate.parsed);
      if (id > 0) {
        addedCount++;
        if (candidate.unaddedSmsId != null) {
          await _db.deleteUnaddedSms(candidate.unaddedSmsId!);
        }
      }
    }

    widget.onAdded?.call();

    if (!mounted) return;
    Navigator.of(context).pop(addedCount);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          addedCount > 0
              ? 'Added $addedCount transaction${addedCount == 1 ? '' : 's'} to your ledger.'
              : 'Selected transactions were already in your ledger.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Found Transactions'),
        actions: [
          if (widget.onShare != null)
            IconButton(
              onPressed: widget.onShare,
              icon: const Icon(Icons.ios_share),
              tooltip: 'Share this format on GitHub',
            ),
          if (_candidates.isNotEmpty)
            TextButton.icon(
              onPressed: _isSaving ? null : _toggleSelectAll,
              icon: Icon(
                _allSelected ? Icons.deselect : Icons.select_all,
                size: 18,
              ),
              label: Text(_allSelected ? 'Deselect all' : 'Select all'),
            ),
        ],
      ),
      body: _candidates.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No new transactions to review',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All SMS messages in your inbox are already recorded.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Summary bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$_selectedCount of ${_candidates.length} selected · Total: ${_money.format(_selectedTotal)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Candidate list
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _candidates.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (BuildContext context, int index) {
                      final CandidateTransaction item = _candidates[index];
                      final ParsedSms sms = item.parsed;
                      final bool isCredit = sms.direction == TxnDirection.credit;

                      return Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: item.selected
                                ? colorScheme.primary.withValues(alpha: 0.5)
                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: item.selected ? 1.5 : 1.0,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _isSaving
                              ? null
                              : () {
                                  setState(() => item.selected = !item.selected);
                                },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: item.selected,
                                      onChanged: _isSaving
                                          ? null
                                          : (bool? val) {
                                              setState(() {
                                                item.selected = val ?? false;
                                              });
                                            },
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sms.merchant,
                                            style: theme.textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            sms.hasExplicitTime
                                                ? _dateFormat.format(sms.date)
                                                : _dateOnlyFormat.format(sms.date),
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          '${isCredit ? "+ " : "- "}${_money.format(sms.amount)}',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: isCredit
                                                ? Colors.green
                                                : colorScheme.onSurface,
                                          ),
                                        ),
                                        if (sms.paymentType.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            sms.paymentType,
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                if (item.rawBody.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.rawBody,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _candidates.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: (_isSaving || _selectedCount == 0) ? null : _addSelected,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add),
                  label: Text(
                    _isSaving
                        ? 'Adding transactions...'
                        : 'Add $_selectedCount transaction${_selectedCount == 1 ? '' : 's'} (${_money.format(_selectedTotal)})',
                  ),
                ),
              ),
            ),
    );
  }
}
