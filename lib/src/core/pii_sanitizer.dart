/// Deterministic, zero-dependency PII sanitizer for bank SMS and transaction alerts.
///
/// Automatically scrubs and masks sensitive personal data before any community contribution:
/// - Account numbers & card numbers
/// - Account balances & credit limits
/// - Reference, UTR, and RRN tracking numbers
/// - Phone numbers, emails, and OTP verification codes
///
/// Preserves transactional signals (amount, merchant keyword, transaction direction,
/// bank keywords, and date syntax) so the SMS can be used for RAG exemplars and model training.
library;

class SanitizedResult {
  final String originalText;
  final String sanitizedText;
  final int maskedCount;
  final List<String> detectedEntities;

  const SanitizedResult({
    required this.originalText,
    required this.sanitizedText,
    required this.maskedCount,
    required this.detectedEntities,
  });

  bool get hasRedactions => maskedCount > 0;
}

class PiiSanitizer {
  const PiiSanitizer();

  static const PiiSanitizer instance = PiiSanitizer();

  /// Sanitizes raw transaction text [input] and returns a [SanitizedResult].
  SanitizedResult sanitize(String input) {
    if (input.trim().isEmpty) {
      return SanitizedResult(
        originalText: input,
        sanitizedText: input,
        maskedCount: 0,
        detectedEntities: const <String>[],
      );
    }

    String text = input;
    int count = 0;
    final Set<String> entities = <String>{};

    // 1. Scrub OTPs first to avoid digits being caught by account / balance matchers.
    final RegExp otpRegex = RegExp(
      r'\b(?:otp|one\s*time\s*password|verification\s*code|secret\s*code)(?:[\s:]+|is\s*)+([0-9]{4,8})\b',
      caseSensitive: false,
    );
    if (otpRegex.hasMatch(text)) {
      text = text.replaceAllMapped(otpRegex, (Match m) {
        count++;
        entities.add('OTP / Verification Code');
        final String full = m.group(0)!;
        final String code = m.group(1)!;
        return full.replaceFirst(code, '[OTP]');
      });
    }

    // 2. Scrub Balances and Available Limits
    final RegExp balanceRegex = RegExp(
      r'\b(?:(?:avl|avail|available|total|ledger|clear|effective|acct|a/c)?\s*(?:bal|balance|limit)|bal\s*is|avl\s*lmt)[\s:]*(?:rs\.?|inr|₹)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    if (balanceRegex.hasMatch(text)) {
      text = text.replaceAllMapped(balanceRegex, (Match m) {
        count++;
        entities.add('Account Balance');
        final String full = m.group(0)!;
        final String numVal = m.group(1)!;
        return full.replaceFirst(numVal, '[MASKED]');
      });
    }

    // 3. Scrub Reference, UTR, RRN, and Transaction IDs
    final RegExp refRegex = RegExp(
      r'\b(?:upi\s*ref(?:\s*(?:no\.?|num|id))?|rrn|utr|ref\s*(?:no\.?|num|id)?|txn\s*(?:id|ref|no\.?)|imps\s*ref)[\s:]*([a-zA-Z0-9]{6,22})\b',
      caseSensitive: false,
    );
    if (refRegex.hasMatch(text)) {
      text = text.replaceAllMapped(refRegex, (Match m) {
        count++;
        entities.add('Reference / UTR / RRN');
        final String full = m.group(0)!;
        final String refVal = m.group(1)!;
        return full.replaceFirst(refVal, '[MASKED]');
      });
    }

    // 4. Scrub Email Addresses
    final RegExp emailRegex = RegExp(
      r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
      caseSensitive: false,
    );
    if (emailRegex.hasMatch(text)) {
      text = text.replaceAllMapped(emailRegex, (Match m) {
        count++;
        entities.add('Email Address');
        return '[EMAIL]';
      });
    }

    // 5. Scrub Phone Numbers (10-digit Indian mobile or with country code)
    final RegExp phoneRegex = RegExp(
      r'(?:\+?91[\s-]?)?\b[6-9][0-9]{4}[\s-]?[0-9]{5}\b',
    );
    if (phoneRegex.hasMatch(text)) {
      text = text.replaceAllMapped(phoneRegex, (Match m) {
        count++;
        entities.add('Phone Number');
        return '[PHONE]';
      });
    }

    // 6. Scrub Account Numbers & Card Numbers with preceding keywords
    final RegExp acctKeywordRegex = RegExp(
      r'\b(?:a/c|acct|account|card|credit\s*card|debit\s*card)\s*(?:no\.?|num|number|ending|end)?[\s#:*]*(?:[xX*]+)?([0-9]{4,16})\b',
      caseSensitive: false,
    );
    if (acctKeywordRegex.hasMatch(text)) {
      text = text.replaceAllMapped(acctKeywordRegex, (Match m) {
        count++;
        entities.add('Account / Card Number');
        final String full = m.group(0)!;
        final String digits = m.group(1)!;
        // Keep at most last 4 digits masked as *XXXX or replace completely
        return full.replaceFirst(digits, '*XXXX');
      });
    }

    // 7. Scrub isolated 12-16 digit card/account numbers
    final RegExp longDigitsRegex = RegExp(
      r'\b([0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}(?:[- ]?[0-9]{4})?)\b',
    );
    if (longDigitsRegex.hasMatch(text)) {
      text = text.replaceAllMapped(longDigitsRegex, (Match m) {
        count++;
        entities.add('Card / Account Number');
        return '[CARD_MASKED]';
      });
    }

    return SanitizedResult(
      originalText: input,
      sanitizedText: text,
      maskedCount: count,
      detectedEntities: entities.toList(growable: false)..sort(),
    );
  }
}
