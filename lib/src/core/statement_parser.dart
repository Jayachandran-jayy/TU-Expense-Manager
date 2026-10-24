/// Turning the text of a bank or card statement PDF into spends, and finding
/// the ones the ledger has not recorded yet.
///
/// Pure: the text arrives already extracted (PDFBox on Android, sorted by
/// position), one statement row per line.
library;

import 'parser.dart';

/// One spend found in a statement, with the line it came from for the review
/// screen.
typedef StatementRow = ({ParsedSms parsed, String line});

/// `₹250.00`, `1,500.00`, `3,56,000.00` — statements always print paise.
const String _amt = r'(?<amount>[\d,]+\.\d{2})';

/// HDFC card: `03/10/2026| 13:42 TEST MARKETPLACE PRIVBangalore  C 250.00 l`.
/// The `C` is how the rupee glyph extracts; a `+` before it marks a credit.
final RegExp _hdfcCard = RegExp(
  r'^(?<date>\d{2}/\d{2}/\d{4})\|\s*(?<time>\d{2}:\d{2})\s*(?<desc>.*?)\s*'
  r'(?<credit>\+)?\s*(?:C|₹)\s*'
  '$_amt'
  r'(?:\s+\S+)?$',
);

/// YES card: `16/09/2026 UPI_TEST STORE IND - Ref No: RT26… Miscellaneous Stores 1,500.00 Dr`.
final RegExp _drCr = RegExp(
  r'^(?<date>\d{2}/\d{2}/\d{4})\s+(?<desc>.*?)\s*'
  '$_amt'
  r'\s+(?<dc>Dr|Cr)$',
);

/// HDFC savings: `09/10/26 UPI-TEST SHOP 0000628200000001 09/10/26 40.00 1,000.00`.
/// Withdrawal and deposit share one column in the text, so the direction comes
/// from the closing balance.
final RegExp _savings = RegExp(
  r'^(?<date>\d{2}/\d{2}/\d{2})\s+(?<desc>.*?)\s+(?<ref>\d{8,})\s+\d{2}/\d{2}/\d{2}\s+'
  '$_amt'
  r'\s+(?<balance>[\d,]+\.\d{2})$',
);

/// Masked card number (`1234XXXXXXXX5678`) or account number in the header.
final RegExp _cardNumber = RegExp(r'\b\d{4,6}X{4,}(?<last4>\d{4})\b');
final RegExp _accountNumber = RegExp(r'Account No\s*:\s*\d*(?<last4>\d{4})\b');
final RegExp _openingBalance = RegExp(
  r'Opening Balance.*\n\s*(?<balance>[\d,]+\.\d{2})',
);

/// Every debit in [text], in statement order. Credits (payments received,
/// cashback, surcharge waivers) are left out: this is for finding spends.
/// A name in [knownPaymentTypes] ending in the same last four digits is used
/// for the card or account, so imports land beside the SMS-captured spends.
List<StatementRow> parseStatement(
  String text, {
  Iterable<String> knownPaymentTypes = const <String>[],
}) {
  final String paymentType = _paymentTypeOf(text, knownPaymentTypes);
  double? balance = _money(
    _openingBalance.firstMatch(text)?.namedGroup('balance'),
  );
  final List<StatementRow> rows = <StatementRow>[];
  String previous = '';

  for (final String raw in text.split('\n')) {
    final String line = raw.trim();
    final RegExpMatch? card = _hdfcCard.firstMatch(line);
    final RegExpMatch? drCr = card == null ? _drCr.firstMatch(line) : null;
    final RegExpMatch? savings = card == null && drCr == null
        ? _savings.firstMatch(line)
        : null;
    final RegExpMatch? m = card ?? drCr ?? savings;
    if (m == null) {
      previous = line;
      continue;
    }

    final double amount = _money(m.namedGroup('amount'))!;
    bool isDebit;
    if (savings != null) {
      final double closing = _money(savings.namedGroup('balance'))!;
      // shortcut: with no opening balance the first row is taken as a debit, fine for spend statements.
      isDebit = balance == null || closing < balance;
      balance = closing;
    } else {
      isDebit = card != null
          ? card.namedGroup('credit') == null
          : drCr!.namedGroup('dc') == 'Dr';
    }

    // A long description wraps onto the line above the row in the PDF.
    String desc = m.namedGroup('desc')!;
    if (RegExp(r'(?:Ref No:|\(Ref#)$').hasMatch(previous)) {
      desc = '$previous $desc';
    }
    previous = line;
    if (!isDebit) continue;

    final String? time = card?.namedGroup('time');
    final String reference =
        RegExp(r'Ref No:\s*([A-Z]*\d\w*)').firstMatch(desc)?.group(1) ??
        savings?.namedGroup('ref')!.replaceFirst(RegExp(r'^0+'), '') ??
        '';
    rows.add((
      parsed: ParsedSms(
        amount: amount,
        paymentType: paymentType,
        merchant: _merchantOf(desc),
        date: _dateOf(m.namedGroup('date')!, time),
        direction: TxnDirection.debit,
        reference: reference,
        templateId: 'statement',
        hasExplicitTime: time != null && time != '00:00',
      ),
      line: line,
    ));
  }
  return rows;
}

/// A spend already in the ledger, as [notYetRecorded] compares it.
typedef RecordedSpend = ({double amount, DateTime date, String paymentType});

/// The rows of [rows] that nothing in [recorded] accounts for. A recorded
/// spend of the same amount, within a day, on the same card or account counts,
/// and each one accounts for a single row, so two identical spends on one day
/// need two entries. Same-day pairs are taken first so a neighbouring day
/// cannot steal an exact match.
List<StatementRow> notYetRecorded(
  List<StatementRow> rows,
  List<RecordedSpend> recorded,
) {
  final List<bool> used = List<bool>.filled(recorded.length, false);
  final List<bool> matched = List<bool>.filled(rows.length, false);
  for (final int window in <int>[0, 1]) {
    for (int r = 0; r < rows.length; r++) {
      if (matched[r]) continue;
      final ParsedSms row = rows[r].parsed;
      for (int i = 0; i < recorded.length; i++) {
        if (used[i] ||
            (recorded[i].amount - row.amount).abs() >= 0.005 ||
            _dayGap(recorded[i].date, row.date) > window ||
            !_sameAccount(recorded[i].paymentType, row.paymentType)) {
          continue;
        }
        used[i] = true;
        matched[r] = true;
        break;
      }
    }
  }
  return <StatementRow>[
    for (int r = 0; r < rows.length; r++)
      if (!matched[r]) rows[r],
  ];
}

/// Same last four digits. A name without them (`Cash`, `Unknown`) could be any
/// account, so it is allowed to match.
bool _sameAccount(String a, String b) {
  final RegExp tail = RegExp(r'(\d{4})\D*$');
  final String? x = tail.firstMatch(a)?.group(1);
  final String? y = tail.firstMatch(b)?.group(1);
  return x == null || y == null || x == y;
}

int _dayGap(DateTime a, DateTime b) => DateTime.utc(
  a.year,
  a.month,
  a.day,
).difference(DateTime.utc(b.year, b.month, b.day)).inDays.abs();

double? _money(String? s) =>
    s == null ? null : double.tryParse(s.replaceAll(',', ''));

/// `16/09/2026` or `09/10/26`, with the row's clock time when it has one.
DateTime _dateOf(String date, String? time) {
  final List<int> d = date.split('/').map(int.parse).toList();
  final List<int> t = (time ?? '00:00').split(':').map(int.parse).toList();
  return DateTime(d[2] < 100 ? 2000 + d[2] : d[2], d[1], d[0], t[0], t[1]);
}

/// `UPI_TEST STORE CHENNAI IND - Ref No: RT26… Miscellaneous Stores` →
/// `TEST STORE CHENNAI`, the same name the SMS alert gives.
String _merchantOf(String desc) => cleanMerchantName(desc
    .replaceFirst(RegExp(r'\s*(?:IND\s*)?-\s*Ref No:.*$'), '')
    .replaceFirst(RegExp(r'\s*\(Ref#.*$'), '')
    .trim());

/// The account number wins over a card number, because a savings statement
/// also prints the debit card used at a POS.
String _paymentTypeOf(String text, Iterable<String> known) {
  final String bank = text.contains('YES BANK')
      ? 'YES BANK'
      : text.contains('HDFC')
      ? 'HDFC Bank'
      : '';
  final String? account = _accountNumber.firstMatch(text)?.namedGroup('last4');
  final String? last4 =
      account ?? _cardNumber.firstMatch(text)?.namedGroup('last4');
  if (last4 == null) return 'Unknown';
  for (final String name in known) {
    if (name.endsWith(last4)) return name;
  }
  return account != null
      ? '$bank A/c XX$account'.trim()
      : '$bank Card X$last4'.trim();
}
