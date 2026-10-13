/// What the app remembers about ledger preferences (e.g. tracking received income).
library;

import 'package:shared_preferences/shared_preferences.dart';

/// The stored preferences for the ledger.
class LedgerPrefs {
  const LedgerPrefs();

  static const LedgerPrefs instance = LedgerPrefs();

  static const String _trackReceivedKey = 'ledger.track_received';

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
}
