/// What the app remembers about ledger preferences (e.g. tracking received income).
library;

import 'package:shared_preferences/shared_preferences.dart';

/// The stored preferences for the ledger.
class LedgerPrefs {
  const LedgerPrefs();

  static const LedgerPrefs instance = LedgerPrefs();

  static const String _trackReceivedKey = 'ledger.track_received';
  static const String _aiFallbackKey = 'ledger.ai_fallback_enabled';
  static const String _customModelPathKey = 'ledger.custom_model_path';

  /// Whether received (credit) transactions should be tracked and shown.
  /// Defaults to false (off).
  Future<bool> trackReceived() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_trackReceivedKey) ?? false;
  }

  /// Sets whether received transactions should be tracked and shown.
  Future<void> setTrackReceived(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_trackReceivedKey, value);
  }

  /// Whether on-device AI fallback parsing is enabled. Defaults to false.
  Future<bool> aiFallbackEnabled() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_aiFallbackKey) ?? false;
  }

  /// Sets whether on-device AI fallback parsing is enabled.
  Future<void> setAiFallbackEnabled(bool value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiFallbackKey, value);
  }

  /// Custom GGUF model path picked by user, if any.
  Future<String?> customModelPath() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_customModelPathKey);
  }

  /// Sets custom GGUF model path.
  Future<void> setCustomModelPath(String? path) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_customModelPathKey);
    } else {
      await prefs.setString(_customModelPathKey, path);
    }
  }
}
