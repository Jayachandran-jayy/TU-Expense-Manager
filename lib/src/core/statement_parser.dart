/// Turning the text of a bank or card statement PDF into spends, and finding
/// the ones the ledger has not recorded yet.
///
/// Pure: the text arrives already extracted (PDFBox on Android, sorted by
/// position), one statement row per line. Nothing here knows a bank: a row is
/// any line that opens with a date and closes with an amount.
library;

import 'parser.dart';
import 'pii_sanitizer.dart';

/// One spend found in a statement, with the line it came from for the review
/// screen.
typedef StatementRow = ({ParsedSms parsed, String line});

/// `250.00`, `1,500.00`, `3,56,000.00` — statements always print paise.
const String _money = r'[\d,]+\.\d{2}';
/// A date anywhere in a line: `05.10.2026`, `05 Oct 2026`, `05-Oct-26`, `2026-10-05`.
final RegExp _anyDate = RegExp(r'\b(?:\d{1,2}[-/. ]\w{2,3}[-/. ]\d{2,4}|\d{4}-\d{2}-\d{2})\b');

// Not part of a dotted date such as 05.10.2026.
final RegExp _moneyToken = RegExp('(?<![\\d.])$_money(?![\\d]|\\.\\d)');

/// The end of a row: an optional `+` (credit) and currency mark (`₹`, `Rs`,
/// `INR`, or the `C` the rupee glyph extracts as), the amount, an optional
/// running balance, an optional Dr/Cr/D/C marker, and at most one stray
/// character (HDFC prints a category dot that extracts as `l`).
final RegExp _tail = RegExp(
  r'\s(?<sign>\+)?\s*(?:₹|Rs\.?|INR|C)?\s*(?<amount>' '$_money' r')'
  r'(?:\s+(?<balance>' '$_money' r'))?'
  r'(?:\s*(?<dc>Dr|Cr|DR|CR|D|C)\b\.?)?'
  r'(?:\s+\S)?$',
);

final RegExp _balanceRow = RegExp(
  r'opening balance|closing balance|balance b/?f|balance c/?f|brought forward|carried forward',
  caseSensitive: false,
);
final RegExp _refMarker = RegExp(
  r'\s*(?:\bIND\b\s*)?-?\s*\(?\s*Ref(?:\s*No)?\.?\s*[:#].*$',
  caseSensitive: false,
);
final RegExp _refValue = RegExp(
  r'Ref(?:\s*No)?\.?\s*[:#]\s*([A-Za-z]*\d\w*)',
  caseSensitive: false,
);
final RegExp _wrapsOntoRow = RegExp(r'(?:Ref No:|\(Ref#)$', caseSensitive: false);

/// Masked card number (`1234XXXXXXXX5678`) or account number in the header.
final RegExp _cardNumber = RegExp(r'\b\d{4,6}[X*]{4,}(?<last4>\d{4})\b');
final RegExp _accountNumber = RegExp(
  r'(?<!Alternate )\b(?:Account|A/c)\s*(?:No|Number)\.?\s*:\s*[X*\d]*?(?<last4>\d{4})\b',
);
final RegExp _openingBalance = RegExp(
  'Opening Balance.*\\n\\s*(?<balance>$_money)',
);

typedef _Row = ({
  DateTime date,
  bool hasTime,
  String desc,
  double amount,
  double? balance,
  String sign,
  String dc,
});

/// [line] read as a statement row, or null when it is not one.
_Row? _rowOf(String line) {
  // HDFC cards print `18/09/2026| 15:38`.
  final String flat = line.replaceFirst('|', ' ');
  final lead = SmsParser.leadingDate(flat);
  if (lead == null) return null;
  final RegExpMatch? tail = _tail.firstMatch(flat);
  if (tail == null || tail.start < lead.end) return null;
  return (
    date: lead.date,
    hasTime: lead.hasTime && (lead.date.hour != 0 || lead.date.minute != 0),
    desc: flat.substring(lead.end, tail.start).trim(),
    amount: _parseMoney(tail.namedGroup('amount'))!,
    balance: _parseMoney(tail.namedGroup('balance')),
    sign: tail.namedGroup('sign') ?? '',
    dc: (tail.namedGroup('dc') ?? '').toUpperCase(),
  );
}

/// Every debit in [text], in statement order. Credits (payments received,
/// cashback, surcharge waivers) are left out: this is for finding spends.
/// A name in [knownPaymentTypes] ending in the same last four digits is used
/// for the card or account, so imports land beside the SMS-captured spends.
List<StatementRow> parseStatement(
  String text, {
  Iterable<String> knownPaymentTypes = const <String>[],
}) {
  final String paymentType = statementPaymentType(text, knownPaymentTypes);
  double? balance = _parseMoney(
    _openingBalance.firstMatch(text)?.namedGroup('balance'),
  );
  final List<StatementRow> rows = <StatementRow>[];
  String previous = '';

  for (final String raw in text.split('\n')) {
    final String line = raw.trim();
    final _Row? row = _rowOf(line);
    if (row == null) {
      previous = line;
      continue;
    }
    final String above = previous;
    previous = line;

    if (_balanceRow.hasMatch(row.desc)) {
      balance = row.balance ?? row.amount;
      continue;
    }
    // shortcut: a bank that prints 0.00 in the empty withdrawal or deposit column
    // reads as a zero row and is skipped; split the columns if one turns up.
    if (row.amount == 0) continue;

    final bool isDebit;
    if (row.dc.isNotEmpty) {
      isDebit = row.dc.startsWith('D');
    } else if (row.balance != null) {
      // shortcut: with no opening balance the first row is taken as a debit, fine for spend statements.
      isDebit = balance == null || row.balance! < balance;
    } else {
      isDebit = row.sign != '+';
    }
    if (row.balance != null) balance = row.balance;
    if (!isDebit) continue;

    // A long description wraps onto the line above the row in the PDF.
    final String desc = _wrapsOntoRow.hasMatch(above) || _merchantOf(row.desc).isEmpty
        ? '$above ${row.desc}'
        : row.desc;
    rows.add((
      parsed: ParsedSms(
        amount: row.amount,
        paymentType: paymentType,
        merchant: _merchantOf(desc),
        date: row.date,
        direction: TxnDirection.debit,
        reference: _referenceOf(desc),
        templateId: 'statement',
        hasExplicitTime: row.hasTime,
      ),
      line: line,
    ));
  }
  return rows;
}

/// Lines worth handing to the on-device model when no row was recognised:
/// every line carrying both an amount and a date, which leaves out totals,
/// limits and other summary figures.
List<String> statementCandidateLines(String text) => <String>[
  for (final String raw in text.split('\n'))
    if (_moneyToken.hasMatch(raw) && _anyDate.hasMatch(raw)) raw.trim(),
];

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

/// A short, masked sample of the statement's layout for a public GitHub issue:
/// the column header and up to [maxRows] rows. The name and address block is
/// never included, because only rows are taken. Card and account numbers,
/// references, long digit runs and running balances are masked.
String statementExcerpt(String text, {int maxRows = 10}) {
  final List<String> lines = text.split('\n').map((String l) => l.trim()).toList();
  final String header = lines.firstWhere(
    (String l) =>
        RegExp(r'^date\b', caseSensitive: false).hasMatch(l) &&
        RegExp(r'amount|narration|description|details|withdrawal|debit', caseSensitive: false)
            .hasMatch(l),
    orElse: () => '',
  );
  List<String> rows = lines.where((String l) => _rowOf(l) != null).take(maxRows).toList();
  if (rows.isEmpty) {
    // Unknown layout: lines with both an amount and a date somewhere in them.
    rows = lines
        .where((String l) => _moneyToken.hasMatch(l) && _anyDate.hasMatch(l))
        .take(maxRows)
        .toList();
  }
  const PiiSanitizer sanitizer = PiiSanitizer();
  return <String>[
    if (header.isNotEmpty) header,
    for (final String row in rows) _maskRow(sanitizer.sanitize(row).sanitizedText),
  ].join('\n');
}

String _maskRow(String row) {
  String masked = row
      .replaceAll(_cardNumber, '[CARD]')
      .replaceAll(RegExp(r'\d{6,}'), '[MASKED]');
  final List<RegExpMatch> amounts = _moneyToken.allMatches(masked).toList();
  if (amounts.length > 1) {
    final RegExpMatch last = amounts.last;
    masked = masked.replaceRange(last.start, last.end, '[BALANCE]');
  }
  return masked;
}

/// `HDFC Bank`, `YES Bank` — the bank the statement names most often (a row
/// can name another bank, like an ACH debit), for an issue title. Empty when
/// none is found.
String statementBankHint(String text) {
  final Map<String, int> counts = <String, int>{};
  for (final RegExpMatch m in RegExp(r'\b([A-Z]{2,})\s+(?:BANK|Bank)\b').allMatches(text)) {
    counts.update(m.group(1)!, (int n) => n + 1, ifAbsent: () => 1);
  }
  if (counts.isEmpty) return '';
  final String top = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  return '$top Bank';
}

/// The card or account the statement is for. A name in [known] with the same
/// last four digits wins, so imports land on the name SMS alerts already use.
/// The account number beats a card number, because a savings statement also
/// prints the debit card used at a POS.
String statementPaymentType(String text, Iterable<String> known) {
  final String? account = _accountNumber.firstMatch(text)?.namedGroup('last4');
  final String? last4 = account ?? _cardNumber.firstMatch(text)?.namedGroup('last4');
  if (last4 == null) return 'Unknown';
  for (final String name in known) {
    if (name.endsWith(last4)) return name;
  }
  return account != null ? 'A/c XX$account' : 'Card X$last4';
}

/// Same last four digits. A name without them (`Cash`, `Unknown`) could be any
/// account, so it is allowed to match.
bool _sameAccount(String a, String b) {
  final RegExp tail = RegExp(r'(\d{4})\D*$');
  final String? x = tail.firstMatch(a)?.group(1);
  final String? y = tail.firstMatch(b)?.group(1);
  return x == null || y == null || x == y;
}

int _dayGap(DateTime a, DateTime b) => DateTime.utc(a.year, a.month, a.day)
    .difference(DateTime.utc(b.year, b.month, b.day))
    .inDays
    .abs();

double? _parseMoney(String? s) =>
    s == null ? null : double.tryParse(s.replaceAll(',', ''));

/// `UPI_TEST STORE CHENNAI IND - Ref No: RT26… Miscellaneous Stores` →
/// `TEST STORE CHENNAI`, the same name the SMS alert gives. Reference numbers
/// and value dates printed inside the narration are dropped.
String _merchantOf(String desc) => cleanMerchantName(
  desc
      .replaceFirst(_refMarker, '')
      .replaceAll(RegExp(r'\b\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}\b'), '')
      .replaceAll(RegExp(r'\b\d{8,}\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceFirst(RegExp(r'[\s/_.-]+$'), '')
      .trim(),
);

/// The `Ref No:` / `Ref#` value, else the first long number in the narration.
String _referenceOf(String desc) =>
    _refValue.firstMatch(desc)?.group(1) ??
    RegExp(r'\b\d{10,}\b').firstMatch(desc)?.group(0)?.replaceFirst(RegExp(r'^0+'), '') ??
    '';
