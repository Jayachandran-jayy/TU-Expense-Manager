/// Parsing bank transaction emails and pasted email text into structured transactions.
///
/// Pure Dart: zero Flutter dependencies. Supports stripped HTML and plain text emails
/// from major Indian card issuers (HDFC, ICICI, SBI Card, Axis, Yes Bank, Kotak, IndusInd)
/// as well as a flexible universal fallback parser.
library;

import 'parser.dart';

/// A transaction extracted from an email body or snippet.
class ParsedEmail {
  const ParsedEmail({
    required this.amount,
    required this.paymentType,
    required this.merchant,
    required this.date,
    required this.direction,
    this.reference = '',
    this.bank = '',
    this.rawSnippet = '',
    this.hasExplicitTime = true,
  });

  final double amount;
  final String paymentType;
  final String merchant;
  final DateTime date;
  final TxnDirection direction;
  final String reference;
  final String bank;
  final String rawSnippet;
  final bool hasExplicitTime;

  bool get isCredit => direction == TxnDirection.credit;

  /// Converts this parsed email transaction into a [ParsedSms] so it can cleanly
  /// pass through identical database insertion and deduplication pipelines.
  ParsedSms toParsedSms() => ParsedSms(
        amount: amount,
        paymentType: paymentType,
        merchant: merchant,
        date: date,
        direction: direction,
        reference: reference,
        templateId: bank.isNotEmpty ? 'email_$bank' : 'email',
        hasExplicitTime: hasExplicitTime,
      );

  @override
  String toString() =>
      'ParsedEmail($amount, $paymentType, $merchant, ${date.toIso8601String()}, '
      '${direction.name}, ref: $reference, bank: $bank, explicitTime: $hasExplicitTime)';
}

/// Core parser for email text and HTML bodies.
class EmailParser {
  EmailParser._();

  /// Converts an HTML email body into plain readable text suitable for regex parsing.
  static String stripHtml(String html) {
    if (html.isEmpty) return '';

    var text = html;

    // Remove comments
    text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

    // Remove style and script blocks entirely
    text = text.replaceAll(
        RegExp(r'<(?:style|script)[^>]*>[\s\S]*?<\/(?:style|script)>',
            caseSensitive: false),
        '');

    // Replace line-break tags with newlines
    text = text.replaceAll(
        RegExp(r'<(?:br|br\s*\/|\/p|\/div|\/tr|\/h[1-6])>',
            caseSensitive: false),
        '\n');

    // Replace table cell ends with spaces
    text = text.replaceAll(
        RegExp(r'<\/(?:td|th)>', caseSensitive: false), ' ');

    // Strip remaining HTML tags
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');

    // Decode standard and numeric HTML entities
    text = _decodeHtmlEntities(text);

    // Normalize multiple spaces into single spaces while keeping line breaks
    final lines = text.split('\n').map((line) => line.replaceAll(RegExp(r'[ \t\r\f]+'), ' ').trim());
    return lines.where((line) => line.isNotEmpty).join('\n');
  }

  static String _decodeHtmlEntities(String text) {
    var s = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&#8377;', '₹')
        .replaceAll('&#x20b9;', '₹')
        .replaceAll('&#x20B9;', '₹')
        .replaceAll('&zwnj;', '')
        .replaceAll('&zwj;', '');

    // Decimal entities: &#123;
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.tryParse(match.group(1)!);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    // Hex entities: &#x1F600;
    s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.tryParse(match.group(1)!, radix: 16);
      return code != null ? String.fromCharCode(code) : match.group(0)!;
    });

    return s;
  }

  /// Parses arbitrary email text or HTML into a [ParsedEmail].
  ///
  /// Returns `null` if no recognizable transaction pattern is detected.
  static ParsedEmail? parse(String rawText, {DateTime? fallbackDate}) {
    final text = stripHtml(rawText);
    if (text.trim().isEmpty) return null;

    // Try issuer-specific templates first for highest accuracy
    final parsed = _parseHdfc(text, fallbackDate) ??
        _parseIcici(text, fallbackDate) ??
        _parseSbi(text, fallbackDate) ??
        _parseAxis(text, fallbackDate) ??
        _parseYes(text, fallbackDate) ??
        _parseKotak(text, fallbackDate) ??
        _parseIndusInd(text, fallbackDate) ??
        _parseGeneric(text, fallbackDate);

    return parsed;
  }

  // ---------------------------------------------------------------------------
  // ISSUER TEMPLATES
  // ---------------------------------------------------------------------------

  /// HDFC Bank credit/debit card alerts
  static ParsedEmail? _parseHdfc(String text, DateTime? fallbackDate) {
    if (!RegExp(r'hdfc\s*bank', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    // Pattern 1: Thank you for using your HDFC Bank Credit Card ending in 1234 for INR 1,500.00 at AMAZON on 22-09-2026 14:30:15
    final p1 = RegExp(
      r'using your HDFC Bank (?:Credit|Debit) Card ending (?:in\s+)?(\d{4}) for (?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?) at (.+?) on (\d{1,2}[-/]\d{1,2}[-/]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]m)?)?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p1 != null) {
      final card = 'HDFC Bank Card ${p1.group(1)}';
      final amt = _parseAmount(p1.group(2)!);
      final rawMerchant = p1.group(3)!.trim();
      final stamp = _parseDate(p1.group(4)!, fallbackDate);
      if (amt != null && stamp != null) {
        final ref = _extractAuthOrRef(text);
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: ref,
          bank: 'hdfc',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    // Pattern 2: INR 450.00 has been debited from your HDFC Bank A/c / Card ending 9012 towards SWIGGY on 21-09-2026
    final p2 = RegExp(
      r'(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?)\s+(?:has been |is )?debited from (?:your )?HDFC Bank (?:A\/c|Card) ending (?:in\s+)?(\d{4})\s+(?:at|to|towards)\s+(.+?)\s+on\s+(\d{1,2}[-/]\d{1,2}[-/]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]m)?)?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p2 != null) {
      final amt = _parseAmount(p2.group(1)!);
      final card = 'HDFC Bank Card ${p2.group(2)}';
      final rawMerchant = p2.group(3)!.trim();
      final stamp = _parseDate(p2.group(4)!, fallbackDate);
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'hdfc',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    // Pattern 3: Alert: You have spent Rs. 849.00 on your HDFC Bank Card ending 5678 at ZOMATO on 20-09-2026
    final p3 = RegExp(
      r'spent (?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?) on (?:your )?HDFC Bank (?:Credit )?Card ending (?:in\s+)?(\d{4}) at (.+?) on (\d{1,2}[-/]\d{1,2}[-/]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]m)?)?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p3 != null) {
      final amt = _parseAmount(p3.group(1)!);
      final card = 'HDFC Bank Card ${p3.group(2)}';
      final rawMerchant = p3.group(3)!.trim();
      final stamp = _parseDate(p3.group(4)!, fallbackDate);
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'hdfc',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    return null;
  }

  /// ICICI Bank credit/debit card alerts
  static ParsedEmail? _parseIcici(String text, DateTime? fallbackDate) {
    if (!RegExp(r'icici\s*bank', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    // Pattern 1: Your ICICI Bank Credit Card XX1004 has been used for a transaction of INR 2,499.00 on Sep 21, 2026 at 11:20:00. Info: FLIPKART.
    final p1 = RegExp(
      r'ICICI Bank (?:Credit|Debit) Card (?:ending in\s+|XX)?(\d{4}) has been used for a transaction of (?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?) on (.+?)\.\s+Info:\s*([A-Za-z0-9\s._&/-]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p1 != null) {
      final card = 'ICICI Bank Card ${p1.group(1)}';
      final amt = _parseAmount(p1.group(2)!);
      final rawDate = p1.group(3)!.trim();
      final rawMerchant = p1.group(4)!.split('.').first.trim();
      final stamp = _parseDate(rawDate, fallbackDate);
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'icici',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    // Pattern 2: ICICI Bank Card ending 1004 was used for a purchase of Rs. 1,200.00 on 22-09-2026 at RELIANCE
    final p2 = RegExp(
      r'ICICI Bank (?:Credit|Debit)?\s*Card ending (?:in\s+)?(\d{4}) (?:was used for a purchase of|was used for)\s+(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?)\s+on\s+(.+?)\s+at\s+([A-Za-z0-9\s._&/-]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p2 != null) {
      final card = 'ICICI Bank Card ${p2.group(1)}';
      final amt = _parseAmount(p2.group(2)!);
      final rawDate = p2.group(3)!.trim();
      final rawMerchant = p2.group(4)!.split('.').first.trim();
      final stamp = _parseDate(rawDate, fallbackDate);
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'icici',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    return null;
  }

  /// SBI Card alerts
  static ParsedEmail? _parseSbi(String text, DateTime? fallbackDate) {
    if (!RegExp(r'sbi\s*(?:credit\s*)?card', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    // Pattern 1: Thank you for using your SBI Credit Card ending 4321 for Rs. 1,299.00 at MYNTRA on 22/09/2026
    final p1 = RegExp(
      r'using your SBI (?:Credit )?Card ending (?:in\s+)?(\d{4}) for (?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?) at (.+?) on (\d{1,2}[-/]\d{1,2}[-/]\d{2,4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (p1 != null) {
      final card = 'SBI Card ${p1.group(1)}';
      final amt = _parseAmount(p1.group(2)!);
      final rawMerchant = p1.group(3)!.trim();
      final stamp = _parseDate(p1.group(4)!, fallbackDate);
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'sbi',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    // Pattern 2: Your SBI Card ending 4321 was used to make a purchase of Rs. 450.00 on 21/09/2026 at RELIANCE RETAIL
    final p2 = RegExp(
      r'SBI Card ending (?:in\s+)?(\d{4}) was used (?:to make a purchase of|for)\s+(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?)\s+on\s+(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\s+at\s+(.+?)(?:\.|\s+Ref|$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p2 != null) {
      final card = 'SBI Card ${p2.group(1)}';
      final amt = _parseAmount(p2.group(2)!);
      final stamp = _parseDate(p2.group(3)!, fallbackDate);
      final rawMerchant = p2.group(4)!.trim();
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'sbi',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    return null;
  }

  /// Axis Bank alerts
  static ParsedEmail? _parseAxis(String text, DateTime? fallbackDate) {
    if (!RegExp(r'axis\s*bank', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    // Pattern 1: Your Axis Bank Card no. XX3456 was used for INR 850.00 on 22-09-2026 18:30:00 at STARBUCKS.
    final p1 = RegExp(
      r'Axis Bank Card (?:no\.?\s*)?(?:XX)?(\d{4}) was used for (?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?) on (\d{1,2}[-/]\d{1,2}[-/]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)\s+at\s+(.+?)(?:\.|\s+Available|\s+Avl|$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p1 != null) {
      final card = 'Axis Bank Card ${p1.group(1)}';
      final amt = _parseAmount(p1.group(2)!);
      final stamp = _parseDate(p1.group(3)!, fallbackDate);
      final rawMerchant = p1.group(4)!.trim();
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'axis',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    return null;
  }

  /// YES Bank alerts
  static ParsedEmail? _parseYes(String text, DateTime? fallbackDate) {
    if (!RegExp(r'yes\s*bank', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    // Pattern 1: INR 204.00 spent on YES BANK Card X2858 at UPI_GEORGE EGG CENTRE 13-08-2026 09:21:35 am
    final p1 = RegExp(
      r'(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?) spent on YES BANK (?:Credit )?Card (?:ending |X)?(\d{4}) (?:at|@)\s*(.+?)\s+(\d{1,2}[-/]\d{1,2}[-/]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]m)?)?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p1 != null) {
      final amt = _parseAmount(p1.group(1)!);
      final card = 'YES BANK Card ${p1.group(2)}';
      final rawMerchant = p1.group(3)!.trim();
      final stamp = _parseDate(p1.group(4)!, fallbackDate);
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'yes',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    return null;
  }

  /// Kotak Mahindra Bank alerts
  static ParsedEmail? _parseKotak(String text, DateTime? fallbackDate) {
    if (!RegExp(r'kotak', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    final p1 = RegExp(
      r'(?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?) (?:was spent|spent) on your Kotak (?:Credit|Debit) Card ending (?:in\s+)?(\d{4}) on (\d{1,2}[-/]\d{1,2}[-/]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?)\s+at\s+(.+?)(?:\.|\s+Avl|$)',
      caseSensitive: false,
    ).firstMatch(text);
    if (p1 != null) {
      final amt = _parseAmount(p1.group(1)!);
      final card = 'Kotak Card ${p1.group(2)}';
      final stamp = _parseDate(p1.group(3)!, fallbackDate);
      final rawMerchant = p1.group(4)!.trim();
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'kotak',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    return null;
  }

  /// IndusInd Bank alerts
  static ParsedEmail? _parseIndusInd(String text, DateTime? fallbackDate) {
    if (!RegExp(r'indusind', caseSensitive: false).hasMatch(text)) {
      return null;
    }

    final p1 = RegExp(
      r'using your IndusInd Bank (?:Credit|Debit) Card ending (?:in\s+)?(\d{4}) for (?:INR|Rs\.?|₹)\s*([\d,]+(?:\.\d{1,2})?) at (.+?) on (\d{1,2}[-/]\d{1,2}[-/]\d{2,4})',
      caseSensitive: false,
    ).firstMatch(text);
    if (p1 != null) {
      final card = 'IndusInd Bank Card ${p1.group(1)}';
      final amt = _parseAmount(p1.group(2)!);
      final rawMerchant = p1.group(3)!.trim();
      final stamp = _parseDate(p1.group(4)!, fallbackDate);
      if (amt != null && stamp != null) {
        return ParsedEmail(
          amount: amt,
          paymentType: card,
          merchant: cleanMerchantName(rawMerchant),
          date: stamp.date,
          direction: TxnDirection.debit,
          reference: _extractAuthOrRef(text),
          bank: 'indusind',
          hasExplicitTime: stamp.hasTime,
        );
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // UNIVERSAL FALLBACK EXTRACTOR
  // ---------------------------------------------------------------------------

  /// Flexible fallback that identifies transaction attributes across arbitrary emails.
  static ParsedEmail? _parseGeneric(String text, DateTime? fallbackDate) {
    // 1. Amount
    final amt = extractAmountOnly(text);
    if (amt == null || amt <= 0) return null;

    // 2. Instrument / Card
    final instrument = extractInstrumentOnly(text) ?? 'Credit Card';

    // 3. Merchant
    final merchant = extractMerchantOnly(text);
    if (merchant == null || merchant.isEmpty) return null;

    // 4. Date & Time
    final stamp = extractDateOnly(text, fallbackDate: fallbackDate) ??
        DateStamp(fallbackDate ?? DateTime.now(), hasTime: false);

    // 5. Direction
    final isCredit = RegExp(
      r'\b(?:refund|credited|cashback|payment received|credit of)\b',
      caseSensitive: false,
    ).hasMatch(text);

    // 6. Reference
    final ref = _extractAuthOrRef(text);

    return ParsedEmail(
      amount: amt,
      paymentType: instrument,
      merchant: cleanMerchantName(merchant),
      date: stamp.date,
      direction: isCredit ? TxnDirection.credit : TxnDirection.debit,
      reference: ref,
      bank: 'generic',
      hasExplicitTime: stamp.hasTime,
    );
  }

  // ---------------------------------------------------------------------------
  // PUBLIC EXTRACTION HELPERS (For prefilling forms even if full parse fails)
  // ---------------------------------------------------------------------------

  /// Extracts transaction amount from arbitrary email snippet.
  static double? extractAmountOnly(String text) {
    final clean = stripHtml(text);
    // INR 1,234.50 or Rs. 1234 or ₹ 450.00
    final match = RegExp(
      r'(?:INR|Rs\.?|₹|INR\s+|Rs\.\s*)\s*([\d,]+(?:\.\d{1,2})?)',
      caseSensitive: false,
    ).firstMatch(clean);
    if (match != null) {
      return _parseAmount(match.group(1)!);
    }
    // Trailing currency: 500.00 INR
    final matchPost = RegExp(
      r'([\d,]+(?:\.\d{1,2})?)\s*(?:INR|Rs\.?|₹)',
      caseSensitive: false,
    ).firstMatch(clean);
    if (matchPost != null) {
      return _parseAmount(matchPost.group(1)!);
    }
    return null;
  }

  /// Extracts card or bank account instrument string.
  static String? extractInstrumentOnly(String text) {
    final clean = stripHtml(text);

    // Explicit named card pattern: e.g. "Federal Bank Card ending in 4567" or "HDFC Bank Credit Card 1234"
    final namedCard = RegExp(
      r'([A-Za-z]+(?:\s+[A-Za-z]+)?\s+(?:Bank\s+)?(?:Credit\s+Card|Debit\s+Card|Card|A\/c))(?:\s+no\.?|\s+ending(?:\s+in)?)?[\s:X*#-]+(\d{3,4})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (namedCard != null) {
      var bankAndType = namedCard.group(1)!.replaceAll(RegExp(r'\s+'), ' ').trim();
      bankAndType = bankAndType.replaceFirst(
        RegExp(r'^(?:alert\s+(?:for|on)\s+|alert\s+|on\s+|your\s+|the\s+|using\s+|via\s+|from\s+|for\s+|to\s+)+', caseSensitive: false),
        '',
      ).trim();
      final digits = namedCard.group(2)!;
      if (bankAndType.isNotEmpty) {
        return '$bankAndType $digits';
      }
    }

    // Generic "Card ending 1234" or "Card XX1234" or "Card ending in 1234"
    final cardDigits = RegExp(
      r'(?:Credit\s+Card|Debit\s+Card|Card|Account|A\/c)(?:\s+no\.?|\s+ending(?:\s+in)?)?[\s:X*#-]+(\d{3,4})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (cardDigits != null) {
      return 'Card ${cardDigits.group(1)}';
    }

    return null;
  }

  /// Extracts merchant name from email context.
  static String? extractMerchantOnly(String text) {
    final clean = stripHtml(text);

    // "at MERCHANT on" or "towards MERCHANT" or "from MERCHANT" or "info: MERCHANT"
    final atMatch = RegExp(
      r'(?:at|to|towards|info:\s*|merchant:\s*|from)\s+([A-Za-z0-9\s._&/-]{2,35}?)(?=\s+(?:on|at|\.|\r|\n|ref|avl|available|limit|by|via)|$)',
      caseSensitive: false,
    ).firstMatch(clean);
    if (atMatch != null) {
      var candidate = atMatch.group(1)!.trim();
      candidate = candidate.replaceAll(RegExp(r'[\s.,;:/-]+$'), '').trim();
      if (candidate.isNotEmpty && !_isGenericStopword(candidate)) {
        return cleanMerchantName(candidate);
      }
    }

    return null;
  }

  /// Extracts timestamp from email text.
  static DateStamp? extractDateOnly(String text, {DateTime? fallbackDate}) {
    final clean = stripHtml(text);

    // e.g. 22-09-2026 or 22/09/2026 or 22-Sep-2026 with optional time
    final dateMatch = RegExp(
      r'(\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]m)?)?)',
      caseSensitive: false,
    ).firstMatch(clean);
    if (dateMatch != null) {
      return _parseDate(dateMatch.group(1)!, fallbackDate);
    }

    // e.g. Sep 21, 2026 or 21-Sep-2026
    final namedMatch = RegExp(
      r'((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{2,4}(?:\s+(?:at\s+)?\d{1,2}:\d{2}(?::\d{2})?(?:\s*[ap]m)?)?)',
      caseSensitive: false,
    ).firstMatch(clean);
    if (namedMatch != null) {
      return _parseDate(namedMatch.group(1)!, fallbackDate);
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // INTERNAL HELPERS
  // ---------------------------------------------------------------------------

  static double? _parseAmount(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  static String _extractAuthOrRef(String text) {
    final match = RegExp(
      r'\b(?:auth(?:entication)?\s*code|ref(?:\.?\s*no\.?|\.|\b)|reference|utr(?:\s*no\.?)?|txn\s*(?:id|no\.?)?)[\s:]*([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(text);
    return match != null ? match.group(1)!.trim() : '';
  }

  static bool _isGenericStopword(String value) {
    final lower = value.toLowerCase().trim();
    return lower == 'your' ||
        lower == 'the' ||
        lower == 'a' ||
        lower == 'an' ||
        lower == 'inr' ||
        lower == 'rs' ||
        lower.startsWith('hdfc') ||
        lower.startsWith('icici') ||
        lower.startsWith('sbi') ||
        lower.startsWith('axis');
  }

  static DateStamp? _parseDate(String raw, DateTime? fallback) {
    final trimmed = raw.trim();

    // 1. DD-MM-YYYY or DD/MM/YYYY with optional time
    final numeric = RegExp(
      r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([ap]m))?)?',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (numeric != null) {
      final day = int.parse(numeric.group(1)!);
      final month = int.parse(numeric.group(2)!);
      var year = int.parse(numeric.group(3)!);
      if (year < 100) year += 2000;

      final hasTime = numeric.group(4) != null;
      var hour = hasTime ? int.parse(numeric.group(4)!) : 0;
      final minute = hasTime ? int.parse(numeric.group(5)!) : 0;
      final second = (hasTime && numeric.group(6) != null) ? int.parse(numeric.group(6)!) : 0;
      final meridiem = numeric.group(7)?.toLowerCase();
      if (meridiem == 'pm' && hour != 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;

      return _buildStamp(year: year, month: month, day: day, hour: hour, minute: minute, second: second, hasTime: hasTime);
    }

    // 2. DD-Mon-YYYY (e.g. 21-Sep-2026 or 21-Sep-26)
    final dmyNamed = RegExp(
      r'^(\d{1,2})[- ]([A-Za-z]{3,9})[- ](\d{2,4})(?:\s+(?:at\s+)?(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([ap]m))?)?',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (dmyNamed != null) {
      final day = int.parse(dmyNamed.group(1)!);
      final monthName = dmyNamed.group(2)!.toLowerCase();
      final month = _months[monthName];
      if (month == null) return null;
      var year = int.parse(dmyNamed.group(3)!);
      if (year < 100) year += 2000;

      final hasTime = dmyNamed.group(4) != null;
      var hour = hasTime ? int.parse(dmyNamed.group(4)!) : 0;
      final minute = hasTime ? int.parse(dmyNamed.group(5)!) : 0;
      final second = (hasTime && dmyNamed.group(6) != null) ? int.parse(dmyNamed.group(6)!) : 0;
      final meridiem = dmyNamed.group(7)?.toLowerCase();
      if (meridiem == 'pm' && hour != 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;

      return _buildStamp(year: year, month: month, day: day, hour: hour, minute: minute, second: second, hasTime: hasTime);
    }

    // 3. Mon DD, YYYY (e.g. Sep 21, 2026 at 11:20:00)
    final mdyNamed = RegExp(
      r'^([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(\d{2,4})(?:\s+(?:at\s+)?(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*([ap]m))?)?',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (mdyNamed != null) {
      final monthName = mdyNamed.group(1)!.toLowerCase();
      final month = _months[monthName];
      if (month == null) return null;
      final day = int.parse(mdyNamed.group(2)!);
      var year = int.parse(mdyNamed.group(3)!);
      if (year < 100) year += 2000;

      final hasTime = mdyNamed.group(4) != null;
      var hour = hasTime ? int.parse(mdyNamed.group(4)!) : 0;
      final minute = hasTime ? int.parse(mdyNamed.group(5)!) : 0;
      final second = (hasTime && mdyNamed.group(6) != null) ? int.parse(mdyNamed.group(6)!) : 0;
      final meridiem = mdyNamed.group(7)?.toLowerCase();
      if (meridiem == 'pm' && hour != 12) hour += 12;
      if (meridiem == 'am' && hour == 12) hour = 0;

      return _buildStamp(year: year, month: month, day: day, hour: hour, minute: minute, second: second, hasTime: hasTime);
    }

    return null;
  }

  static DateStamp? _buildStamp({
    required int year,
    required int month,
    required int day,
    required int hour,
    required int minute,
    required int second,
    required bool hasTime,
  }) {
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59 || second > 59) return null;
    return DateStamp(
      DateTime(year, month, day, hour, minute, second),
      hasTime: hasTime,
    );
  }

  static const Map<String, int> _months = <String, int>{
    'jan': 1,
    'january': 1,
    'feb': 2,
    'february': 2,
    'mar': 3,
    'march': 3,
    'apr': 4,
    'april': 4,
    'may': 5,
    'jun': 6,
    'june': 6,
    'jul': 7,
    'july': 7,
    'aug': 8,
    'august': 8,
    'sep': 9,
    'september': 9,
    'oct': 10,
    'october': 10,
    'nov': 11,
    'november': 11,
    'dec': 12,
    'december': 12,
  };
}

class DateStamp {
  const DateStamp(this.date, {required this.hasTime});
  final DateTime date;
  final bool hasTime;
}
