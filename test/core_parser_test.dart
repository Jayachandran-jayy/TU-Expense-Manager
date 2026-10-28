import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/parser.dart';
import 'package:tu_expense_tracker/src/core/rag_exemplars.dart';

void main() {
  group('SmsParser', () {
    test('looksLikeTransaction matches HDFC loose templates', () {
      const sms1 = 'Amt Deducted! Rs.11500 from your HDFC Bank A/c XX0444 for NEFT txn via HDFC Bank Online Banking Not you?Call 18002586161/SMS BLOCK OB to 7308080808';
      const sms2 = 'Txn Rs.755.00\nOn HDFC Bank Card 8174\nAt hathwaymobileapp.76062993 \nby UPI 250214536533\nOn 01-09\nNot You?';
      
      expect(SmsParser.looksLikeTransaction(sms1), isTrue);
      expect(SmsParser.looksLikeTransaction(sms2), isTrue);
    });
    
    test('looksLikeTransaction ignores random texts', () {
      expect(SmsParser.looksLikeTransaction('Hey, how are you?'), isFalse);
      expect(SmsParser.looksLikeTransaction('Your OTP is 123456'), isFalse);
    });

    test('extractAmountOnly finds the amount in a message a full parse would reject', () {
      // No recognisable merchant/date shape, so SmsParser.parse returns null —
      // this is exactly what ends up in the unadded-SMS inbox.
      const sms = 'Amt Deducted! Rs.11500 from your HDFC Bank A/c XX0444 for '
          'something the date/merchant patterns do not recognise';
      expect(SmsParser.parse(sms), isNull);
      expect(SmsParser.extractAmountOnly(sms), 11500);
    });

    test('extractAmountOnly handles Indian grouping and decimals', () {
      expect(SmsParser.extractAmountOnly('INR 3,99,614.00 blocked'), 399614.00);
      expect(SmsParser.extractAmountOnly('₹53 spent'), 53);
    });

    test('extractAmountOnly returns null when there is nothing to find', () {
      expect(SmsParser.extractAmountOnly('Your OTP is 123456'), isNull);
      expect(SmsParser.extractAmountOnly(''), isNull);
    });

    test('parses HDFC RuPay card UPI transaction with short date and trailing @', () {
      const sms = 'Txn Rs.506.90\n'
          'On HDFC Bank Card 8174\n'
          'At SV2512112258548450219373@ \n'
          'by UPI 789574846858\n'
          'On 13-09\n'
          'Not You?\n'
          'Call 18002586161/SMS BLOCK CC 8174 to 7308080808';

      final receivedAt = DateTime(2026, 9, 13, 8, 14, 21);
      final parsed = SmsParser.parse(sms, receivedAt: receivedAt);

      expect(parsed, isNotNull);
      expect(parsed!.templateId, 'hdfc_card_upi');
      expect(parsed.amount, 506.90);
      expect(parsed.paymentType, 'HDFC Bank Card 8174');
      // Trailing @ stripped cleanly
      expect(parsed.merchant, 'SV2512112258548450219373');
      expect(parsed.reference, '789574846858');
      expect(parsed.direction, TxnDirection.debit);
      expect(parsed.hasExplicitTime, isFalse);
      // Borrows arrival time because SMS arrived on same day
      expect(parsed.date, receivedAt);
    });

    test('parses HDFC RuPay card UPI transaction with Hathway merchant name', () {
      const sms = 'Txn Rs.755.00\n'
          'On HDFC Bank Card 8174\n'
          'At hathwaymobileapp.76062993 \n'
          'by UPI 250214536533\n'
          'On 01-09\n'
          'Not You?';

      final parsed = SmsParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.templateId, 'hdfc_card_upi');
      expect(parsed.amount, 755.0);
      expect(parsed.paymentType, 'HDFC Bank Card 8174');
      expect(parsed.merchant, 'hathwaymobileapp.76062993');
      expect(parsed.reference, '250214536533');
      expect(parsed.date.month, 9);
      expect(parsed.date.day, 1);
    });

    test('parses HDFC RuPay card UPI single-line format', () {
      const sms = 'Txn Rs.506.90 On HDFC Bank Card 8174 At SV2512112258548450219373@ by UPI 789574846858 On 13-09 Not You?';
      final parsed = SmsParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.templateId, 'hdfc_card_upi');
      expect(parsed.amount, 506.90);
      expect(parsed.paymentType, 'HDFC Bank Card 8174');
      expect(parsed.merchant, 'SV2512112258548450219373');
      expect(parsed.reference, '789574846858');
    });

    test('extractInstrumentOnly extracts card or account from various message formats', () {
      const sms1 = 'Txn Rs.506.90\nOn HDFC Bank Card 8174\nAt SV2512112258548450219373@ \nby UPI 789574846858\nOn 13-09';
      expect(SmsParser.extractInstrumentOnly(sms1), 'HDFC Bank Card 8174');

      const sms2 = 'Amt Deducted! Rs.11500 from your HDFC Bank A/c XX0444 for NEFT txn';
      expect(SmsParser.extractInstrumentOnly(sms2), 'HDFC Bank A/c XX0444');

      const sms3 = 'INR 204.00 spent on YES BANK Card X2858 @UPI_GEORGE EGG CENTRE';
      expect(SmsParser.extractInstrumentOnly(sms3), 'YES BANK Card X2858');

      expect(SmsParser.extractInstrumentOnly('Your OTP is 123456'), isNull);
    });

    test('extractMerchantOnly extracts merchant name accurately', () {
      expect(SmsParser.extractMerchantOnly('spent at STARBUCKS on 22-09-2026'), 'STARBUCKS');
      expect(SmsParser.extractMerchantOnly('paid to SWIGGY. Ref 123456'), 'SWIGGY');
      expect(SmsParser.extractMerchantOnly('towards AMAZON on 10/08/26'), 'AMAZON');
      expect(SmsParser.extractMerchantOnly('random message with no merchant'), isNull);
    });

    test('extractDateOnly extracts explicit time and falls back to receivedAt', () {
      // Explicit clock time in message
      final d1 = SmsParser.extractDateOnly(
        'Spent Rs.500 at STORE on 13-08-2026, 09:21:35 am',
        receivedAt: DateTime(2026, 8, 13, 12, 0, 0),
      );
      expect(d1?.year, 2026);
      expect(d1?.month, 8);
      expect(d1?.day, 13);
      expect(d1?.hour, 9);
      expect(d1?.minute, 21);
      expect(d1?.second, 35);

      // No clock time in message, borrows receivedAt time
      final d2 = SmsParser.extractDateOnly(
        'Spent Rs.500 at STORE on 13-08-2026',
        receivedAt: DateTime(2026, 8, 14, 15, 30, 45),
      );
      expect(d2?.year, 2026);
      expect(d2?.month, 8);
      expect(d2?.day, 13);
      expect(d2?.hour, 15);
      expect(d2?.minute, 30);
      expect(d2?.second, 45);

      // Short date format with time
      final d3 = SmsParser.extractDateOnly(
        'Sent Rs.200 to FRIEND on 13-09 14:30',
        receivedAt: DateTime(2026, 9, 13, 10, 0, 0),
      );
      expect(d3?.month, 9);
      expect(d3?.day, 13);
      expect(d3?.hour, 14);
      expect(d3?.minute, 30);
    });

    test('parses various date and time formats in SMS bodies', () {
      // ISO with space
      final parsed1 = SmsParser.parse(
        'Spent Rs.122.02 From HDFC Bank Card 6824 At INNOVATIVE RETAIL CONC On 2026-08-13 07:19:26',
      );
      expect(parsed1, isNotNull);
      expect(parsed1!.date, DateTime(2026, 8, 13, 7, 19, 26));

      // With comma separator and AM/PM
      final parsed2 = SmsParser.parse(
        'INR 204.00 spent on YES BANK Card X2858 @UPI_GEORGE EGG CENTRE 13-08-2026, 09:21:35 am. Avl Lmt INR 281,496.08.',
      );
      expect(parsed2, isNotNull);
      expect(parsed2!.date, DateTime(2026, 8, 13, 9, 21, 35));

      // Month name first
      final parsed3 = SmsParser.parse(
        'INR 160.00 spent using ICICI Bank Card XX8008 on Sep 21, 2026 at 11:20:00 on AMAZON PAY IN G.',
      );
      expect(parsed3, isNotNull);
      expect(parsed3!.date, DateTime(2026, 9, 21, 11, 20, 0));
    });

    test('parses Indian Bank UPI debit with inverted date and RRN', () {
      const sms = 'Sent Rs.90.00 from A/c *4668 on 12-10-26 to M/S.RAJALAKSHMI EDUCATION SERV.RRN 316719288101.Avl Bal Rs.778.39.Not you?SMS BLOCK to 9289592895-Indian Bank.';
      final parsed = SmsParser.parse(sms);

      expect(parsed, isNotNull);
      expect(parsed!.templateId, 'indian_bank_upi_sent');
      expect(parsed.amount, 90.00);
      expect(parsed.paymentType, 'A/c *4668');
      expect(parsed.merchant, 'RAJALAKSHMI EDUCATION SERV');
      expect(parsed.reference, '316719288101');
      expect(parsed.direction, TxnDirection.debit);
      expect(parsed.isCredit, isFalse);
    });

    test('parses HDFC multiline and single-line user templates', () {
      const multiline1 = '''Sent Rs.50000.00
From HDFC Bank A/C *2041
To B rajamalar Princy Rajama
On 12/10/26
Ref 628514613614
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808''';
      final p1 = SmsParser.parse(multiline1);
      expect(p1, isNotNull);
      expect(p1!.amount, 50000.00);
      expect(p1.merchant, 'B rajamalar Princy Rajama');
      expect(p1.reference, '628514613614');
      expect(p1.direction, TxnDirection.debit);

      const cardAlert = 'Spent Rs.2 On HDFC Bank Card 8174 At PPINAPPAUTH On 2026-10-07:20:57:59.Not You? To Block+Reissue Call 18002586161/SMS BLOCK CC 8174 to 7308080808';
      final p2 = SmsParser.parse(cardAlert);
      expect(p2, isNotNull);
      expect(p2!.amount, 2.0);
      expect(p2.merchant, 'PPINAPPAUTH');
      expect(p2.direction, TxnDirection.debit);

      const multiline2 = '''Sent Rs.10.00
From HDFC Bank A/C *0444
To SSURIYA
On 11/10/26
Ref 131131522384
Not You?
Call 18002586161/SMS BLOCK UPI to 7308080808''';
      final p3 = SmsParser.parse(multiline2);
      expect(p3, isNotNull);
      expect(p3!.amount, 10.00);
      expect(p3.merchant, 'SSURIYA');
      expect(p3.reference, '131131522384');
      expect(p3.direction, TxnDirection.debit);
    });

    test('parses YES Bank card SMS template', () {
      const sms = 'INR 55.00 spent on YES BANK Card X2858 @UPI_K M PROWIN INDUSTR 09-10-2026 11:00:46 am. Avl Lmt INR 284,919.00. SMS BLKCC 2858 to 9840909000 if not you';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 55.00);
      expect(p.merchant, 'K M PROWIN INDUSTR');
      expect(p.direction, TxnDirection.debit);
    });

    test('parses YES Bank card SMS with merchant containing month-prefix word and trailing store number', () {
      const sms = 'INR 135.00 spent on YES BANK Card X2858 @UPI_KK SUPER MARKET 1 14-10-2026 10:30:25 am. Avl Lmt INR 283,964.00. SMS BLKCC 2858 to 9840909000 if not you.';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 135.00);
      expect(p.merchant, 'KK SUPER MARKET 1');
      expect(p.paymentType, 'YES BANK Card X2858');
      expect(p.direction, TxnDirection.debit);
      expect(p.date, DateTime(2026, 10, 14, 10, 30, 25));
      expect(p.hasExplicitTime, isTrue);
      expect(p.templateId, 'yes_card');
    });

    test('parses alerts with merchants containing month prefix words without false matching', () {
      const smsDecathlon = 'INR 899.00 spent on YES BANK Card X2858 @DECATHLON 5 14-10-2026 05:20:10 pm. Avl Lmt INR 283,000.00.';
      final pDec = SmsParser.parse(smsDecathlon);
      expect(pDec, isNotNull);
      expect(pDec!.merchant, 'DECATHLON 5');
      expect(pDec.amount, 899.00);
      expect(pDec.date, DateTime(2026, 10, 14, 17, 20, 10));

      const smsFullMonth = 'INR 250.00 spent on YES BANK Card X2858 @COFFEE CAFE 14-October-2026 11:15:00 am.';
      final pMonth = SmsParser.parse(smsFullMonth);
      expect(pMonth, isNotNull);
      expect(pMonth!.date.month, 10);
      expect(pMonth.date.day, 14);
    });

    test('parses SBI debited alert with space in Ref no and VPA cleaning', () {
      const sms = 'Dear Customer, your a/c no. XXXXXXXX1234 is debited by Rs. 500.00 on 12-10-26 by UPI-ZOMATO-zomato@icici. Ref no 428192019283. Available bal: Rs. 14,500.25. -SBI';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 500.00);
      expect(p.merchant, 'ZOMATO');
      expect(p.reference, '428192019283');
      expect(p.direction, TxnDirection.debit);
    });

    test('parses Acct debited with alert', () {
      const sms = 'Acct XX456 has been debited with INR 299.00 on 12-Oct-26 for UPI-SWIGGY. Bal: INR 8,210.50. Call 18002662 for dispute.';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 299.00);
      expect(p.merchant, 'SWIGGY');
      expect(p.direction, TxnDirection.debit);
    });

    test('parses Axis Bank alert with POS- prefix', () {
      const sms = 'Axis Bank Alert: Your A/C no. XXXXXX7890 is debited for INR 450.00 on 12-10-26. Info: POS-STARBUCKS. Available Balance: INR 12,300.00.';
      final p = SmsParser.parse(sms);
      expect(p, isNotNull);
      expect(p!.amount, 450.00);
      expect(p.merchant, 'STARBUCKS');
      expect(p.direction, TxnDirection.debit);
    });

    test('parses credit alerts correctly and preserves debit direction for PZCREDIT', () {
      const creditSms = 'A/c *1234 credited with INR 1,500.00 on 12-10-26 by EMPLOYER Ref 987654321';
      final pCredit = SmsParser.parse(creditSms);
      expect(pCredit, isNotNull);
      expect(pCredit!.amount, 1500.00);
      expect(pCredit.direction, TxnDirection.credit);
      expect(pCredit.isCredit, isTrue);

      // Debit alert containing "CREDIT" in merchant name must remain debit
      const pzCreditSms = 'Spent Rs.39791.72 From HDFC Bank Card x2227 At PZCREDIT9772829 On 2026-08-11:06:08:24 Bal Rs.210943.42';
      final pDebit = SmsParser.parse(pzCreditSms);
      expect(pDebit, isNotNull);
      expect(pDebit!.direction, TxnDirection.debit);
      expect(pDebit.isCredit, isFalse);
    });

    test('parses Kotak, Canara, BOB, IDFC, Federal, PNB, and Union Bank templates', () {
      // 1. Kotak Mahindra Debit
      const kotakDebit = 'Rs 250.00 debited from a/c no. **1234 on 12-10-26 to SWIGGY Ref:123456789. Avail Bal: Rs 5000.00.';
      final pKotakD = SmsParser.parse(kotakDebit);
      expect(pKotakD, isNotNull);
      expect(pKotakD!.amount, 250.00);
      expect(pKotakD.merchant, 'SWIGGY');
      expect(pKotakD.reference, '123456789');
      expect(pKotakD.direction, TxnDirection.debit);

      // 2. Kotak Mahindra Credit
      const kotakCredit = 'Acct XX1234 credited by Rs 1200.00 on 12-10-26-Info: SALARY. Bal: Rs 45000.00.';
      final pKotakC = SmsParser.parse(kotakCredit);
      expect(pKotakC, isNotNull);
      expect(pKotakC!.amount, 1200.00);
      expect(pKotakC.merchant, 'SALARY');
      expect(pKotakC.direction, TxnDirection.credit);
      expect(pKotakC.isCredit, isTrue);

      // 3. Canara Bank Debit
      const canaraDebit = 'A/C 1234 debited by INR 500.00 on 12-10-26 10:30 trf to FLIPKART - Canara Bank. Bal: INR 12000.00.';
      final pCanaraD = SmsParser.parse(canaraDebit);
      expect(pCanaraD, isNotNull);
      expect(pCanaraD!.amount, 500.00);
      expect(pCanaraD.merchant, 'FLIPKART');
      expect(pCanaraD.direction, TxnDirection.debit);

      // 4. Canara Bank Credit
      const canaraCredit = 'A/C 1234 credited by INR 5000.00 on 12-10-26 10:30 by GOOGLE INDIA - Canara Bank. Bal: INR 17000.00.';
      final pCanaraC = SmsParser.parse(canaraCredit);
      expect(pCanaraC, isNotNull);
      expect(pCanaraC!.amount, 5000.00);
      expect(pCanaraC.merchant, 'GOOGLE INDIA');
      expect(pCanaraC.direction, TxnDirection.credit);
      expect(pCanaraC.isCredit, isTrue);

      // 5. Bank of Baroda Debit
      const bobDebit = 'Bob A/c XX1234 debited by INR 350.00 on 12-10-26 towards UBER Ref 9876543210 Bal: INR 4500.00.';
      final pBobD = SmsParser.parse(bobDebit);
      expect(pBobD, isNotNull);
      expect(pBobD!.amount, 350.00);
      expect(pBobD.merchant, 'UBER');
      expect(pBobD.reference, '9876543210');
      expect(pBobD.direction, TxnDirection.debit);

      // 6. IDFC FIRST Bank Debit
      const idfcDebit = 'INR 850.00 debited from A/c XX5678 on 12-10-26 14:20:00 txn-UPI AMAZON. Available Balance: INR 25400.00.';
      final pIdfcD = SmsParser.parse(idfcDebit);
      expect(pIdfcD, isNotNull);
      expect(pIdfcD!.amount, 850.00);
      expect(pIdfcD.merchant, 'AMAZON');
      expect(pIdfcD.direction, TxnDirection.debit);

      // 7. Federal Bank Debit
      const fedDebit = 'Dear Customer, A/C X9012 is debited by Rs. 2450.00 on 12-OCT-26 infavour of AMAZON. Bal: Rs. 15000.00.';
      final pFedD = SmsParser.parse(fedDebit);
      expect(pFedD, isNotNull);
      expect(pFedD!.amount, 2450.00);
      expect(pFedD.merchant, 'AMAZON');
      expect(pFedD.direction, TxnDirection.debit);

      // 8. Punjab National Bank (PNB) Debit
      const pnbDebit = 'Rs.1200.00 debited from PNB A/C *1234 on 12-10-26 by UPI Info: SWIGGY Bal: Rs.8500.00.';
      final pPnbD = SmsParser.parse(pnbDebit);
      expect(pPnbD, isNotNull);
      expect(pPnbD!.amount, 1200.00);
      expect(pPnbD.merchant, 'SWIGGY');
      expect(pPnbD.direction, TxnDirection.debit);

      // 9. Union Bank of India Debit
      const unionDebit = 'Rs 150.00 debited from A/c *1234 on 12-10-26 to CHAI POINT Ref 456789 Bal: Rs 3400.00.';
      final pUnionD = SmsParser.parse(unionDebit);
      expect(pUnionD, isNotNull);
      expect(pUnionD!.amount, 150.00);
      expect(pUnionD.merchant, 'CHAI POINT');
      expect(pUnionD.reference, '456789');
      expect(pUnionD.direction, TxnDirection.debit);

      // 10. HDFC Credit with date preceding sender
      const hdfcCredit = 'Rs.500.00 credited to HDFC Bank A/c XX0444 on 11/08/26 from RAPIDO Ref 123456789';
      final pHdfcC = SmsParser.parse(hdfcCredit);
      expect(pHdfcC, isNotNull);
      expect(pHdfcC!.amount, 500.00);
      expect(pHdfcC.merchant, 'RAPIDO');
      expect(pHdfcC.reference, '123456789');
      expect(pHdfcC.direction, TxnDirection.credit);
      expect(pHdfcC.isCredit, isTrue);
    });

    test('parses HDFC Bank BillPay SMS formats from issues #89, #90, and #91', () {
      // Issue #89: ICICI Prudential Mutual Fund
      const sms89 = 'Bill Paid!\n'
          'ICICIPruMF Bill XXBROKER-XXXXXX of Rs. 1000.00 paid on 07-Oct-2026 from HDFC Bank Account XXXXXXXXXXXXXX.\n'
          'BillPay Ref: 987654321012';
      final p89 = SmsParser.parse(sms89);
      expect(p89, isNotNull);
      expect(p89!.templateId, 'hdfc_billpay');
      expect(p89.amount, 1000.0);
      expect(p89.merchant, 'ICICIPruMF');
      expect(p89.paymentType, 'HDFC Bank Account XXXXXXXXXXXXXX');
      expect(p89.reference, '987654321012');
      expect(p89.direction, TxnDirection.debit);
      expect(p89.date.year, 2026);
      expect(p89.date.month, 10);
      expect(p89.date.day, 7);
      expect(p89.hasExplicitTime, isFalse);

      // Issue #90: Axis Mutual Fund
      const sms90 = 'Bill Paid!\n'
          'AxisMF Bill XXXXXX-XXXXXX of Rs. 500.00 paid on 05-Oct-2026 from HDFC Bank Account XXXXXXXXXXXXXX.\n'
          'BillPay Ref: 123456789012';
      final p90 = SmsParser.parse(sms90);
      expect(p90, isNotNull);
      expect(p90!.templateId, 'hdfc_billpay');
      expect(p90.amount, 500.0);
      expect(p90.merchant, 'AxisMF');
      expect(p90.paymentType, 'HDFC Bank Account XXXXXXXXXXXXXX');
      expect(p90.reference, '123456789012');
      expect(p90.direction, TxnDirection.debit);
      expect(p90.date.year, 2026);
      expect(p90.date.month, 10);
      expect(p90.date.day, 5);

      // Issue #91: Mirae Asset Mutual Fund
      const sms91 = 'Bill Paid!\n'
          'MiraeAssetMF Bill XXXXXX-XXXXXX of Rs. 1000.00 paid on 12-Oct-2026 from HDFC Bank Account XXXXXXXXXXXXXX.\n'
          'BillPay Ref: 556677889900';
      final p91 = SmsParser.parse(sms91);
      expect(p91, isNotNull);
      expect(p91!.templateId, 'hdfc_billpay');
      expect(p91.amount, 1000.0);
      expect(p91.merchant, 'MiraeAssetMF');
      expect(p91.paymentType, 'HDFC Bank Account XXXXXXXXXXXXXX');
      expect(p91.reference, '556677889900');
      expect(p91.direction, TxnDirection.debit);
      expect(p91.date.year, 2026);
      expect(p91.date.month, 10);
      expect(p91.date.day, 12);

      // Single-line format without optional bill reference or bill ID
      const singleLine = 'Bill Paid! BESCOM Bill of Rs. 450.50 paid on 01-Nov-2026 from HDFC Bank Account XX5678.';
      final pSingle = SmsParser.parse(singleLine);
      expect(pSingle, isNotNull);
      expect(pSingle!.templateId, 'hdfc_billpay');
      expect(pSingle.amount, 450.50);
      expect(pSingle.merchant, 'BESCOM');
      expect(pSingle.paymentType, 'HDFC Bank Account XX5678');
      expect(pSingle.reference, '');
      expect(pSingle.direction, TxnDirection.debit);
      expect(pSingle.date.month, 11);
      expect(pSingle.date.day, 1);
    });

    test('RagExemplars retrieves hdfc_billpay_debit exemplar for HDFC bill messages', () {
      const sms = 'Bill Paid!\nICICIPruMF Bill XX123 of Rs. 1000 paid on 07-Oct-2026 from HDFC Bank Account XX1234';
      final exemplars = RagExemplars.findBestExemplars(sms, limit: 1);
      expect(exemplars, isNotEmpty);
      expect(exemplars.first.id, 'hdfc_billpay_debit');
      expect(exemplars.first.bank, 'HDFC Bank');
    });
  });
}
