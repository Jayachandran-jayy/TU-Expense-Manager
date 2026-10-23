import 'package:flutter_test/flutter_test.dart';
import 'package:tu_expense_tracker/src/core/contribution_checks.dart';

void main() {
  group('scheduledWordingIn', () {
    test('flags a scheduled debit notice', () {
      const sms = 'Payment of INR 1673.00 towards Merchant Policy Bazaar to be debited from ICICI Bank Credit Card, is due by 25/10/2026.';
      expect(scheduledWordingIn(sms), containsAll(<String>['to be debited', 'is due by']));
    });

    test('does not flag a completed debit', () {
      const sms = 'INR 135.00 spent on YES BANK Card X2858 @UPI_KK SUPER MARKET on 14-10-2026. Your account has been debited.';
      expect(scheduledWordingIn(sms), isEmpty);
    });

    test('flags due-date wording with a day number', () {
      expect(scheduledWordingIn('Bill of Rs 900 due on 12/11/2026'), isNotEmpty);
    });

    test('is case-insensitive', () {
      expect(scheduledWordingIn('Amount WILL BE DEBITED on 3 Nov'), isNotEmpty);
    });
  });
}
