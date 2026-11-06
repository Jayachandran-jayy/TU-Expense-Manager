/// Interactive modal dialog for reporting bugs and app issues.
///
/// Pre-fills system diagnostics (app version, Android release, device model)
/// without collecting any financial, personal, or transaction information.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/github_contribution_helper.dart';

class ReportBugDialog extends StatefulWidget {
  const ReportBugDialog({
    super.key,
    this.appVersion,
    this.appBuild,
  });

  final String? appVersion;
  final String? appBuild;

  /// Shows the dialog as a responsive bottom sheet.
  static Future<void> show(
    BuildContext context, {
    String? appVersion,
    String? appBuild,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReportBugDialog(
        appVersion: appVersion,
        appBuild: appBuild,
      ),
    );
  }

  @override
  State<ReportBugDialog> createState() => _ReportBugDialogState();
}

class _ReportBugDialogState extends State<ReportBugDialog> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _stepsController = TextEditingController();

  DeviceDiagnostics? _diagnostics;
  bool _loadingDiagnostics = true;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    final diagnostics = await GitHubContributionHelper.fetchDeviceDiagnostics(
      appVersion: widget.appVersion,
      appBuild: widget.appBuild,
    );
    if (!mounted) return;
    setState(() {
      _diagnostics = diagnostics;
      _loadingDiagnostics = false;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  bool _validateInput() {
    if (_titleController.text.trim().isEmpty) {
      _showMessage('Please enter a brief issue summary.');
      return false;
    }
    if (_descriptionController.text.trim().isEmpty) {
      _showMessage('Please describe the issue or bug.');
      return false;
    }
    return true;
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
      );
  }

  Future<bool> _confirmPublic() async {
    final bool? publish = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post publicly on GitHub?'),
        content: const Text(
          'GitHub issues are public. Anyone can read this bug report, and it is tied to your GitHub account. '
          'The app copies the report to your clipboard and opens the GitHub new issue page. You submit it there.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open GitHub')),
        ],
      ),
    );
    return publish ?? false;
  }

  Future<void> _submitToGitHub() async {
    if (!_validateInput()) return;
    if (!await _confirmPublic()) return;
    if (!mounted) return;

    final diag = _diagnostics ??
        DeviceDiagnostics(
          appVersion: widget.appVersion ?? 'Unknown',
          appBuild: widget.appBuild ?? '',
          deviceModel: 'Android Device',
          osVersion: 'Android',
        );

    final bool opened = await GitHubContributionHelper.launchBugReportFlow(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      stepsToReproduce: _stepsController.text.trim(),
      diagnostics: diag,
    );
    if (!mounted) return;

    Navigator.of(context).pop();
    if (opened) {
      _showMessage('GitHub opened. Tap "Submit new issue" to post it. The text is also on your clipboard.');
    } else {
      _showMessage('Could not open browser. The bug report is on your clipboard to paste into GitHub.');
    }
  }

  void _copyReport() {
    if (!_validateInput()) return;

    final diag = _diagnostics ??
        DeviceDiagnostics(
          appVersion: widget.appVersion ?? 'Unknown',
          appBuild: widget.appBuild ?? '',
          deviceModel: 'Android Device',
          osVersion: 'Android',
        );

    final String report = GitHubContributionHelper.generateBugReportBody(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      stepsToReproduce: _stepsController.text.trim(),
      diagnostics: diag,
    );

    Clipboard.setData(ClipboardData(text: report));
    _showMessage('Bug report copied to clipboard!');
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
                    color: colorScheme.error.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bug_report_outlined, color: colorScheme.error, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Report a Bug',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Report issues directly to GitHub to help us fix them',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Diagnostics & Privacy Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E222B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant.withAlpha(80)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'System Diagnostics',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_loadingDiagnostics)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: LinearProgressIndicator(),
                    )
                  else if (_diagnostics != null) ...[
                    Text(
                      '• App: ${_diagnostics!.appVersion}${_diagnostics!.appBuild.isNotEmpty ? ' (build ${_diagnostics!.appBuild})' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '• Device: ${_diagnostics!.deviceModel}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '• OS: Android ${_diagnostics!.osVersion}${_diagnostics!.sdkInt != null ? ' (API ${_diagnostics!.sdkInt})' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'No financial details, transactions, or SMS contents are ever sent.',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: theme.hintColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Issue Summary Field
            TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Issue Summary *',
                hintText: 'e.g. App freezes after cold start',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Description Field
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              minLines: 2,
              decoration: InputDecoration(
                labelText: 'Description *',
                hintText: 'What went wrong? What did you expect to happen?',
                filled: true,
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Steps to Reproduce Field
            TextField(
              controller: _stepsController,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                labelText: 'Steps to Reproduce (Optional)',
                hintText: '1. Open Settings\n2. Tap...',
                filled: true,
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons
            FilledButton.icon(
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Submit on GitHub'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _submitToGitHub,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy Bug Report'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _copyReport,
            ),
          ],
        ),
      ),
    );
  }
}
