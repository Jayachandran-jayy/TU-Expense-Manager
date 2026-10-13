/// Dedicated full-screen lock view shown when TU Expense Tracker is locked.
library;

import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';

/// Full-screen lock barrier requiring biometric or device passcode authentication.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({
    super.key,
    this.service,
    this.onUnlocked,
  });

  final AppLockService? service;
  final VoidCallback? onUnlocked;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  AppLockService get _service => widget.service ?? AppLockService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptUnlock();
    });
  }

  Future<void> _attemptUnlock() async {
    final bool success = await _service.authenticate();
    if (success && mounted) {
      widget.onUnlocked?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: primary.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 48,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'TU Expense Tracker',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'App is locked to protect your financial data.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  onPressed: _attemptUnlock,
                  icon: const Icon(Icons.fingerprint_rounded, size: 22),
                  label: const Text('Unlock with Biometrics / PIN'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
