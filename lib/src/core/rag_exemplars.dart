/// Curated, code-baked RAG exemplars for on-device bank transaction parsing.
///
/// Runs 100% offline with zero network calls and 0ms latency.
/// Curated patterns are updated and deployed directly with app releases.
library;

class RagExemplar {
  final String id;
  final String bank;
  final List<String> keywords;
  final String rawSms;
  final Map<String, dynamic> expectedJson;

  const RagExemplar({
    required this.id,
    required this.bank,
    required this.keywords,
    required this.rawSms,
    required this.expectedJson,
  });
}

class RagExemplars {
  RagExemplars._();

  static const List<RagExemplar> curated = <RagExemplar>[
    // 1. HDFC Credit Card Debit
    RagExemplar(
      id: 'hdfc_card_debit',
      bank: 'HDFC Bank',
      keywords: <String>['hdfc', 'card', 'spent', 'rs', 'ending'],
      rawSms:
          'Alert: You have spent Rs.450.00 on HDFC Bank Card ending 8174 at SWIGGY on 14-OCT-26. Avail Limit: Rs [MASKED].',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 450.0,
        'currency': 'INR',
        'merchant': 'SWIGGY',
        'account': '8174',
        'reference': null,
        'date': '2026-10-14',
      },
    ),

    // 2. SBI UPI Debit
    RagExemplar(
      id: 'sbi_upi_debit',
      bank: 'State Bank of India',
      keywords: <String>['sbi', 'upi', 'debited', 'transferred', 'vpa', 'ref'],
      rawSms:
          'Dear UPI user A/C *1234 debited by 120.0 on 12Oct26 trf to Blinkit Ref [MASKED]. If not done by you forward this SMS to 9223008333.',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 120.0,
        'currency': 'INR',
        'merchant': 'Blinkit',
        'account': '1234',
        'reference': '[MASKED]',
        'date': '2026-10-12',
      },
    ),

    // 3. ICICI Bank Card / Netbanking
    RagExemplar(
      id: 'icici_card_debit',
      bank: 'ICICI Bank',
      keywords: <String>['icici', 'card', 'debited', 'inr', 'spent'],
      rawSms:
          'Your ICICI Bank Card XX4002 has been used for a transaction of INR 1,599.00 at AMAZON INDIA on 15-Oct-26.',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 1599.0,
        'currency': 'INR',
        'merchant': 'AMAZON INDIA',
        'account': '4002',
        'reference': null,
        'date': '2026-10-15',
      },
    ),

    // 4. Axis Bank UPI
    RagExemplar(
      id: 'axis_upi_debit',
      bank: 'Axis Bank',
      keywords: <String>['axis', 'upi', 'debited', 'vpa', 'ref', 'inr'],
      rawSms:
          'INR 250.00 debited from Axis Bank A/c no. *5678 on 11-10-2026 towards Zomato via UPI. Ref no [MASKED].',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 250.0,
        'currency': 'INR',
        'merchant': 'Zomato',
        'account': '5678',
        'reference': '[MASKED]',
        'date': '2026-10-11',
      },
    ),

    // 5. Kotak Mahindra Bank
    RagExemplar(
      id: 'kotak_card_debit',
      bank: 'Kotak Bank',
      keywords: <String>['kotak', 'spent', 'card', 'bal'],
      rawSms:
          'Sent Rs.80.00 from Kotak Bank A/c *9012 to Chai Point on 10-Oct-26. UPI Ref [MASKED]. Avail Bal Rs [MASKED].',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 80.0,
        'currency': 'INR',
        'merchant': 'Chai Point',
        'account': '9012',
        'reference': '[MASKED]',
        'date': '2026-10-10',
      },
    ),

    // 6. Indian Bank UPI (Special format: Sent Rs.X to M/S...)
    RagExemplar(
      id: 'indian_bank_upi',
      bank: 'Indian Bank',
      keywords: <String>['indian', 'bank', 'sent', 'rs', 'm/s', 'rrn'],
      rawSms:
          'Sent Rs.90.00 from Indian Bank A/c 3210 on 09-10-2026 to M/S RELIANCE RETAIL. RRN [MASKED].',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 90.0,
        'currency': 'INR',
        'merchant': 'RELIANCE RETAIL',
        'account': '3210',
        'reference': '[MASKED]',
        'date': '2026-10-09',
      },
    ),

    // 7. Generic Credit / Refund
    RagExemplar(
      id: 'generic_credit_refund',
      bank: 'General',
      keywords: <String>['credited', 'refund', 'received', 'acct', 'a/c', 'deposited'],
      rawSms:
          'Your A/c *4455 is credited with Rs.350.00 on 13-Oct-26 towards Refund from UBER. UPI Ref [MASKED].',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'credit',
        'amount': 350.0,
        'currency': 'INR',
        'merchant': 'UBER',
        'account': '4455',
        'reference': '[MASKED]',
        'date': '2026-10-13',
      },
    ),

    // 8. Punjab National Bank (PNB)
    RagExemplar(
      id: 'pnb_debit',
      bank: 'PNB',
      keywords: <String>['pnb', 'debited', 'a/c', 'rs', 'txn'],
      rawSms:
          'A/c *6789 debited for Rs.1,100.00 on 08-10-26 by txn at D-MART. Total Bal: Rs [MASKED].',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 1100.0,
        'currency': 'INR',
        'merchant': 'D-MART',
        'account': '6789',
        'reference': null,
        'date': '2026-10-08',
      },
    ),

    // 9. HDFC Bank BillPay
    RagExemplar(
      id: 'hdfc_billpay_debit',
      bank: 'HDFC Bank',
      keywords: <String>['hdfc', 'bill', 'paid', 'rs', 'billpay', 'account'],
      rawSms:
          'Bill Paid!\nICICIPruMF Bill XXBROKER-XXXXXX of Rs. 1000.00 paid on 07-Oct-2026 from HDFC Bank Account XX1234.\nBillPay Ref: [MASKED]',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 1000.0,
        'currency': 'INR',
        'merchant': 'ICICIPruMF',
        'account': '1234',
        'reference': '[MASKED]',
        'date': '2026-10-07',
      },
    ),

    // 10. HDFC Bank Debit Mandate (Issue #95)
    RagExemplar(
      id: 'hdfc_bank_mandate_debit',
      bank: 'HDFC Bank',
      keywords: <String>['hdfc', 'bank', 'debit', 'mandate', 'debited', 'rs'],
      rawSms:
          "Debit Alert! Your HDFC Bank A/c xxxxxx has been debited Rs 1117 on 06th Oct' 2026 via Debit Mandate for RAZORPAY_XXXXXX_XXXXX",
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 1117.0,
        'currency': 'INR',
        'merchant': 'RAZORPAY_XXXXXX_XXXXX',
        'account': 'xxxxxx',
        'reference': '[MASKED]',
        'date': '2026-10-06',
      },
    ),

    // 11. Axis Bank Multi-line UPI Debit (Issue #94)
    RagExemplar(
      id: 'axis_bank_multiline_debit',
      bank: 'Axis Bank',
      keywords: <String>['axis', 'bank', 'debited', 'upi', 'p2m', 'inr'],
      rawSms:
          'INR 3732.00 debited\nA/c no. XXXXXX\n21-10-26, 13:52:41\nUPI/P2M/XXXXXXXXXXXXXX/Sri Kauvery Medical\nNot you? SMS BLOCKUPI Cust ID to XXXXXXXXXXXXXX\nAxis Bank',
      expectedJson: <String, dynamic>{
        'is_transaction': true,
        'type': 'debit',
        'amount': 3732.0,
        'currency': 'INR',
        'merchant': 'Sri Kauvery Medical',
        'account': 'XXXXXX',
        'reference': '[MASKED]',
        'date': '2026-10-21',
      },
    ),
  ];

  /// Finds the top [limit] best matching exemplars for the input [messageText].
  static List<RagExemplar> findBestExemplars(String messageText, {int limit = 2}) {
    if (messageText.trim().isEmpty || curated.isEmpty) {
      return const <RagExemplar>[];
    }

    final String lower = messageText.toLowerCase();
    final Set<String> queryTokens = lower
        .split(RegExp(r'[^a-zA-Z0-9]+'))
        .where((t) => t.length >= 2)
        .toSet();

    final bool isCreditQuery =
        lower.contains('credit') || lower.contains('refund') || lower.contains('received');

    final List<({RagExemplar exemplar, int score})> scored = <({RagExemplar exemplar, int score})>[];

    for (final RagExemplar ex in curated) {
      int score = 0;

      // Bank name check
      if (lower.contains(ex.bank.toLowerCase())) {
        score += 10;
      }

      // Keyword token overlap
      for (final String kw in ex.keywords) {
        if (queryTokens.contains(kw)) {
          score += 2;
        }
      }

      // Direction match
      final bool isCreditEx = ex.expectedJson['type'] == 'credit';
      if (isCreditQuery == isCreditEx) {
        score += 3;
      }

      if (score > 0) {
        scored.add((exemplar: ex, score: score));
      }
    }

    // Sort descending by score
    scored.sort((a, b) => b.score.compareTo(a.score));

    if (scored.isEmpty) {
      // Fallback: return default debit and credit exemplars
      return curated.take(limit).toList();
    }

    return scored.take(limit).map((s) => s.exemplar).toList();
  }
}
