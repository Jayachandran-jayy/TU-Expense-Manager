/// Checks on a contribution before it is sent.
///
/// Pure Dart, so it can run on every platform and be tested without a device.
library;

/// Wording that means a payment is scheduled or due, not yet posted. Samples
/// like this are reminders, not completed transactions, so they are flagged
/// before sending.
final RegExp _scheduledWording = RegExp(
  r'\b(?:to be (?:debited|deducted)|will be (?:debited|deducted)|is due (?:by|on)|due (?:by|on) \d|scheduled (?:for|to be))',
  caseSensitive: false,
);

/// The scheduled-payment phrases found in [text], or an empty list.
List<String> scheduledWordingIn(String text) {
  return _scheduledWording.allMatches(text).map((Match m) => m.group(0)!).toSet().toList(growable: false);
}
