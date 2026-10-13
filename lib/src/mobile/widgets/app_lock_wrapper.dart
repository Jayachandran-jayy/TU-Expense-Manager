/// App lifecycle wrapper that enforces App Lock on pause and background resume.
library;

import 'package:flutter/material.dart';

import '../screens/app_lock_screen.dart';
import '../services/app_lock_service.dart';

/// Wraps the root mobile home view to intercept lifecycle events and present
/// the biometric/passcode lock barrier when locked.
class AppLockWrapper extends StatefulWidget {
  const AppLockWrapper({
    super.key,
    required this.child,
    this.service,
  });

  final Widget child;
  final AppLockService? service;

  @override
  State<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<AppLockWrapper>
    with WidgetsBindingObserver {
  AppLockService get _service => widget.service ?? AppLockService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.initializeSecurity();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app is backgrounded/minimized (paused), lock it immediately
    // if App Lock is enabled in preferences.
    // Inactive is ignored because biometric/system auth prompts cause inactive state.
    if (state == AppLifecycleState.paused) {
      if (!_service.isAuthenticating) {
        _service.checkAndLock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _service.isLocked,
      builder: (BuildContext context, bool locked, Widget? _) {
        if (locked) {
          return AppLockScreen(
            service: _service,
            onUnlocked: () => _service.unlock(),
          );
        }
        return widget.child;
      },
    );
  }
}
