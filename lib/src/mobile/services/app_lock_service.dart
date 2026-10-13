/// On-device app security and authentication service.
///
/// Uses `local_auth` to authenticate with biometrics (fingerprint/face) or
/// device screen lock (PIN/pattern/password).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/ledger_prefs.dart';

/// Service managing biometric and device passcode lock for TU Expense Tracker.
class AppLockService {
  AppLockService({
    LocalAuthentication? auth,
    LedgerPrefs? prefs,
    MethodChannel? channel,
  })  : _auth = auth ?? LocalAuthentication(),
        _prefs = prefs ?? LedgerPrefs.instance,
        _channel =
            channel ?? const MethodChannel('com.tu.expense.manager/telephony');

  static final AppLockService instance = AppLockService();

  final LocalAuthentication _auth;
  final LedgerPrefs _prefs;
  final MethodChannel _channel;

  /// Observable state indicating whether the app is currently locked.
  final ValueNotifier<bool> isLocked = ValueNotifier<bool>(false);

  /// Whether authentication is currently in progress (avoids concurrent prompts).
  bool _isAuthenticating = false;
  bool get isAuthenticating => _isAuthenticating;

  /// Checks if the device supports biometric or screen lock authentication.
  Future<bool> canAuthenticate() async {
    try {
      final bool canCheckBiometrics = await _auth.canCheckBiometrics;
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      return canCheckBiometrics || isDeviceSupported;
    } catch (e) {
      debugPrint('AppLockService: canAuthenticate check failed: $e');
      return false;
    }
  }

  /// Prompts the user to authenticate using biometrics or device passcode.
  Future<bool> authenticate({
    String localizedReason = 'Unlock TU Expense Tracker to access your ledger.',
  }) async {
    if (_isAuthenticating) return false;
    _isAuthenticating = true;
    try {
      final bool didAuthenticate = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (didAuthenticate) {
        isLocked.value = false;
      }
      return didAuthenticate;
    } on PlatformException catch (e) {
      debugPrint('AppLockService: PlatformException during authentication: $e');
      return false;
    } catch (e) {
      debugPrint('AppLockService: error during authentication: $e');
      return false;
    } finally {
      _isAuthenticating = false;
    }
  }

  /// Checks preferences and locks the application if App Lock is enabled.
  Future<void> checkAndLock() async {
    final bool enabled = await _prefs.appLockEnabled();
    if (enabled) {
      isLocked.value = true;
    }
  }

  /// Manually unlocks the application state (e.g. for testing).
  void unlock() {
    isLocked.value = false;
  }

  /// Sets or clears the Android window `FLAG_SECURE` flag based on App Lock status.
  Future<void> updateSecureFlag(bool enable) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('setSecureFlag', <String, dynamic>{
          'secure': enable,
        });
      } catch (e) {
        debugPrint('AppLockService: Failed to update FLAG_SECURE: $e');
      }
    }
  }

  /// Initializes secure window flag on startup according to saved preference.
  Future<void> initializeSecurity() async {
    final bool enabled = await _prefs.appLockEnabled();
    await updateSecureFlag(enabled);
    if (enabled) {
      isLocked.value = true;
    }
  }
}
