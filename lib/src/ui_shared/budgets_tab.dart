/// The Budgets tab: category spending targets, remaining balances, and 3-month trends.
///
/// Shared between mobile and web. Driven by props handed down by the hosting shell.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/ledger.dart';
import '../core/models.dart';
import 'palette.dart';

class BudgetsTab extends StatelessWidget {
  const BudgetsTab({
    super.key,
    required this.transactions,
    required this.categories,
    required this.targetMonth,
    required this.currentMonth,
    required this.money,
    required this.loading,
    required this.onMonthChanged,
    required this.onRefresh,
    required this.onSetBudget,
    this.onViewCategoryTransactions,
  });

  final List<ExpenseTxn> transactions;
  final List<ExpenseCategory> categories;
  final YearMonth targetMonth;
  final YearMonth currentMonth;
  final NumberFormat money;
  final bool loading;
  final ValueChanged<YearMonth> onMonthChanged;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ExpenseCategory category, double? budget) onSetBudget;
  final void Function(ExpenseCategory category, YearMonth month)? onViewCategoryTransactions;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final BudgetReport report = deriveBudgetReport(
      transactions: transactions,
      categories: categories,
      targetMonth: targetMonth,
    );

    return Column(
      children: <Widget>[
        _MonthNavigatorBar(
          targetMonth: targetMonth,
          currentMonth: currentMonth,
          onPreviousMonth: () => onMonthChanged(targetMonth.plus(-1)),
          onNextMonth: () => onMonthChanged(targetMonth.plus(1)),
          onResetCurrent: targetMonth == currentMonth
              ? null
              : () => onMonthChanged(currentMonth),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
              children: <Widget>[
                _OverallBudgetCard(
                  overall: report.overall,
                  targetMonth: targetMonth,
                  money: money,
                ),
                const SizedBox(height: 16),
                if (report.activeBudgets.isNotEmpty) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text(
                      'Active Budgets (${report.activeBudgets.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final summary in report.activeBudgets)
                    _CategoryBudgetCard(
                      summary: summary,
                      money: money,
                      onTap: () => _openBudgetEditor(context, summary.category, summary.budget, summary.averageSpend),
                      onViewTransactions: onViewCategoryTransactions != null
                          ? () => onViewCategoryTransactions!(summary.category, targetMonth)
                          : null,
                    ),
                  const SizedBox(height: 20),
                ],
                if (report.unbudgeted.isNotEmpty) ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Unbudgeted Categories (${report.unbudgeted.length})',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Set monthly targets to stay aware of spending trends.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: report.unbudgeted.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        indent: 64,
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                      itemBuilder: (context, index) {
                        final unb = report.unbudgeted[index];
                        return _UnbudgetedCategoryTile(
                          summary: unb,
                          targetMonth: targetMonth,
                          money: money,
                          onSetBudget: () => _openBudgetEditor(
                            context,
                            unb.category,
                            null,
                            unb.averageSpend,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _openBudgetEditor(
    BuildContext context,
    ExpenseCategory category,
    double? currentBudget,
    double averageSpend,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => _BudgetEditorSheet(
        category: category,
        initialBudget: currentBudget,
        averageSpend: averageSpend,
        money: money,
        onSave: (double? newBudget) async {
          Navigator.of(ctx).pop();
          await onSetBudget(category, newBudget);
        },
      ),
    );
  }
}

class _MonthNavigatorBar extends StatelessWidget {
  const _MonthNavigatorBar({
    required this.targetMonth,
    required this.currentMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    this.onResetCurrent,
  });

  final YearMonth targetMonth;
  final YearMonth currentMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback? onResetCurrent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrent = targetMonth == currentMonth;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            tooltip: 'Previous month',
            onPressed: onPreviousMonth,
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onResetCurrent,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: <Widget>[
                  Text(
                    targetMonth.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (!isCurrent) ...<Widget>[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Current',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            tooltip: 'Next month',
            onPressed: onNextMonth,
          ),
        ],
      ),
    );
  }
}

class _OverallBudgetCard extends StatelessWidget {
  const _OverallBudgetCard({
    required this.overall,
    required this.targetMonth,
    required this.money,
  });

  final OverallBudgetSummary overall;
  final YearMonth targetMonth;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool hasBudgets = overall.budgetedCategoryCount > 0;

    final Color statusColor;
    if (!hasBudgets) {
      statusColor = theme.colorScheme.primary;
    } else if (overall.isOverBudget) {
      statusColor = theme.colorScheme.error;
    } else if (overall.rawRatio >= 0.8) {
      statusColor = Colors.orangeAccent;
    } else {
      statusColor = creditColor(theme);
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  '${targetMonth.label} · Overall Budget',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (hasBudgets)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      overall.isOverBudget
                          ? 'Over budget'
                          : '${money.format(overall.totalRemaining)} left',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasBudgets ? money.format(overall.totalBudget) : 'No Budgets Set',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: hasBudgets ? overall.progress : 0.0,
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Spent: ${money.format(overall.totalSpent)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  hasBudgets
                      ? '${(overall.rawRatio * 100).toStringAsFixed(0)}% · ${overall.budgetedCategoryCount} categories'
                      : 'Tap any category below to set target',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBudgetCard extends StatelessWidget {
  const _CategoryBudgetCard({
    required this.summary,
    required this.money,
    required this.onTap,
    this.onViewTransactions,
  });

  final CategoryBudgetSummary summary;
  final NumberFormat money;
  final VoidCallback onTap;
  final VoidCallback? onViewTransactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color catColor = categoryColor(
      summary.category.name,
      theme.brightness,
      explicitColor: summary.category.color,
    );

    final Color statusColor;
    final String statusLabel;
    if (summary.isOverBudget) {
      statusColor = theme.colorScheme.error;
      final over = summary.currentSpent - summary.budget;
      statusLabel = '-${money.format(over)} over';
    } else if (summary.rawRatio >= 0.8) {
      statusColor = Colors.orangeAccent;
      statusLabel = '${money.format(summary.remaining)} left';
    } else {
      statusColor = creditColor(theme);
      statusLabel = '${money.format(summary.remaining)} left';
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: summary.isOverBudget
              ? theme.colorScheme.error.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Header row
              Row(
                children: <Widget>[
                  CategoryAvatar(
                    category: summary.category.name,
                    explicitIcon: summary.category.icon,
                    explicitColor: summary.category.color,
                    size: 40,
                    fontSize: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          summary.category.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${money.format(summary.budget)} / month',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (summary.isOverBudget) ...<Widget>[
                          Icon(Icons.warning_amber_rounded, size: 14, color: statusColor),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          statusLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onViewTransactions != null) ...<Widget>[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'View transactions',
                      onPressed: onViewTransactions,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: summary.progress,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '${money.format(summary.currentSpent)} spent',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${(summary.rawRatio * 100).toStringAsFixed(0)}% used',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 3-Month Trend Mini-Chart
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          'Last 3 months spend',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Avg: ${money.format(summary.averageSpend)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ThreeMonthMiniBars(
                      lookbackMonths: summary.lookbackMonths,
                      monthSpends: summary.monthSpends,
                      budget: summary.budget,
                      accentColor: catColor,
                      money: money,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThreeMonthMiniBars extends StatelessWidget {
  const _ThreeMonthMiniBars({
    required this.lookbackMonths,
    required this.monthSpends,
    required this.budget,
    required this.accentColor,
    required this.money,
  });

  final List<YearMonth> lookbackMonths;
  final Map<YearMonth, double> monthSpends;
  final double budget;
  final Color accentColor;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final double maxVal = max(
      budget,
      monthSpends.values.fold<double>(0.0, (m, v) => max(m, v)),
    );
    final double safeMax = maxVal > 0 ? maxVal : 1.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: <Widget>[
        for (int i = 0; i < lookbackMonths.length; i++)
          _buildBar(context, i, safeMax),
      ],
    );
  }

  Widget _buildBar(BuildContext context, int index, double safeMax) {
    final theme = Theme.of(context);
    final m = lookbackMonths[index];
    final spend = monthSpends[m] ?? 0.0;
    final isTarget = index == lookbackMonths.length - 1;
    final isOver = budget > 0 && spend > budget;
    final double barHeightRatio = (spend / safeMax).clamp(0.05, 1.0);

    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            _compactMoney(spend),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: isTarget ? FontWeight.bold : FontWeight.normal,
              color: isOver ? theme.colorScheme.error : null,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 32,
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 32 * barHeightRatio,
              width: 14,
              decoration: BoxDecoration(
                color: isOver
                    ? theme.colorScheme.error
                    : (isTarget
                        ? accentColor
                        : accentColor.withValues(alpha: 0.4)),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('MMM').format(DateTime(m.year, m.month)),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: isTarget ? FontWeight.bold : FontWeight.w500,
              color: isTarget
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  String _compactMoney(double val) {
    if (val >= 100000) {
      return '₹${(val / 100000).toStringAsFixed(1)}L';
    } else if (val >= 1000) {
      return '₹${(val / 1000).toStringAsFixed(1)}k';
    }
    return '₹${val.toStringAsFixed(0)}';
  }
}

class _UnbudgetedCategoryTile extends StatelessWidget {
  const _UnbudgetedCategoryTile({
    required this.summary,
    required this.targetMonth,
    required this.money,
    required this.onSetBudget,
  });

  final UnbudgetedCategorySummary summary;
  final YearMonth targetMonth;
  final NumberFormat money;
  final VoidCallback onSetBudget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onSetBudget,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: <Widget>[
            CategoryAvatar(
              category: summary.category.name,
              explicitIcon: summary.category.icon,
              explicitColor: summary.category.color,
              size: 38,
              fontSize: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    summary.category.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    summary.currentSpent > 0
                        ? '${targetMonth.label}: ${money.format(summary.currentSpent)}'
                        : (summary.averageSpend > 0
                            ? '3-mo avg: ${money.format(summary.averageSpend)}'
                            : 'No recent spends'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Set budget'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onSetBudget,
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetEditorSheet extends StatefulWidget {
  const _BudgetEditorSheet({
    required this.category,
    required this.initialBudget,
    required this.averageSpend,
    required this.money,
    required this.onSave,
  });

  final ExpenseCategory category;
  final double? initialBudget;
  final double averageSpend;
  final NumberFormat money;
  final Future<void> Function(double? newBudget) onSave;

  @override
  State<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends State<_BudgetEditorSheet> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialBudget;
    _controller = TextEditingController(
      text: initial != null && initial > 0 ? initial.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _removeBudget() async {
    setState(() => _saving = true);
    await widget.onSave(null);
  }

  Future<void> _submit([double? overrideValue]) async {
    setState(() => _saving = true);
    if (overrideValue != null) {
      await widget.onSave(overrideValue);
      return;
    }

    final raw = _controller.text.trim();
    if (raw.isEmpty) {
      await widget.onSave(null);
      return;
    }

    final parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0) {
      setState(() {
        _error = 'Please enter a valid amount';
        _saving = false;
      });
      return;
    }

    await widget.onSave(parsed <= 0 ? null : parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initialBudget != null && widget.initialBudget! > 0;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header
          Row(
            children: <Widget>[
              CategoryAvatar(
                category: widget.category.name,
                explicitIcon: widget.category.icon,
                explicitColor: widget.category.color,
                size: 44,
                fontSize: 22,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isEditing ? 'Edit Category Budget' : 'Set Category Budget',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      widget.category.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.averageSpend > 0) ...<Widget>[
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _controller.text = widget.averageSpend.round().toString();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.lightbulb_outline, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Past 3-month average: ${widget.money.format(widget.averageSpend)} (Tap to use)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monthly Budget Target',
              prefixText: '₹ ',
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _saving ? null : () => _submit(),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Budget', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (isEditing) ...<Widget>[
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: _saving ? null : _removeBudget,
              child: const Text('Remove Budget Target'),
            ),
          ],
        ],
      ),
    );
  }
}
