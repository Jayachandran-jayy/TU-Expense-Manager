import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tu_expense_tracker/src/core/ledger_prefs.dart';
import 'package:tu_expense_tracker/src/mobile/services/contribution_uploader.dart';

/// Records every request and answers with [respond].
class _SpyClient extends http.BaseClient {
  _SpyClient(this.respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest) respond;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond(request);
  }
}

http.StreamedResponse _status(int code) => http.StreamedResponse(Stream.value(<int>[]), code);

const String _baseUrl = 'https://example.supabase.co';
const String _anonKey = 'anon-test-key';

const SmsContribution _sample = SmsContribution(
  bank: 'HDFC Bank',
  txnType: 'debit',
  amount: 350,
  merchant: 'Blinkit',
  sanitizedSms: 'Spent Rs.350 on HDFC Card ending *XXXX at Blinkit.',
);

ContributionUploader _uploader(_SpyClient client) => ContributionUploader(
      client: client,
      prefs: LedgerPrefs.instance,
      baseUrl: _baseUrl,
      anonKey: _anonKey,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('sends nothing when the user has not opted in', () async {
    final _SpyClient client = _SpyClient((_) async => _status(201));

    final ContributionResult result = await _uploader(client).send(_sample);

    expect(result, ContributionResult.disabled);
    expect(client.requests, isEmpty);
  });

  test('sends nothing when no backend is configured', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'ledger.contribute_enabled': true});
    final _SpyClient client = _SpyClient((_) async => _status(201));
    final ContributionUploader uploader = ContributionUploader(
      client: client,
      baseUrl: '',
      anonKey: '',
    );

    expect(await uploader.send(_sample), ContributionResult.notConfigured);
    expect(client.requests, isEmpty);
  });

  test('posts only the reviewed fields with the anon key when opted in', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'ledger.contribute_enabled': true});
    final _SpyClient client = _SpyClient((_) async => _status(201));

    final ContributionResult result = await _uploader(client).send(_sample);

    expect(result, ContributionResult.sent);
    expect(client.requests, hasLength(1));
    final http.Request request = client.requests.single as http.Request;
    expect(request.method, 'POST');
    expect(request.url.toString(), '$_baseUrl/rest/v1/sms_contributions');
    expect(request.headers['apikey'], _anonKey);
    expect(request.headers['Authorization'], 'Bearer $_anonKey');
    expect(request.headers['Prefer'], 'return=minimal');

    final Map<String, dynamic> body = jsonDecode(request.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), <String>{'bank', 'txn_type', 'amount', 'merchant', 'sanitized_sms'});
    expect(body['txn_type'], 'debit');
    expect(body['amount'], 350);
  });

  test('refuses text that still holds personal details, without sending', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'ledger.contribute_enabled': true});
    final _SpyClient client = _SpyClient((_) async => _status(201));
    const SmsContribution leaky = SmsContribution(
      bank: 'SBI',
      txnType: 'debit',
      amount: 10,
      merchant: 'Shop',
      sanitizedSms: 'Paid to shop@okaxis for Rs 10 from A/c 54321',
    );

    final ContributionResult result = await _uploader(client).send(leaky);

    expect(result, ContributionResult.hasPersonalDetails);
    expect(client.requests, isEmpty);
  });

  test('refuses text over the length cap, without sending', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'ledger.contribute_enabled': true});
    final _SpyClient client = _SpyClient((_) async => _status(201));
    final SmsContribution long = SmsContribution(
      bank: 'SBI',
      txnType: 'debit',
      amount: 10,
      merchant: 'Shop',
      sanitizedSms: 'Spent Rs 10 at Shop. ' * 100,
    );

    expect(await _uploader(client).send(long), ContributionResult.tooLong);
    expect(client.requests, isEmpty);
  });

  test('reports a server error as rejected', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'ledger.contribute_enabled': true});
    final _SpyClient client = _SpyClient((_) async => _status(401));

    expect(await _uploader(client).send(_sample), ContributionResult.rejected);
  });

  test('reports a dropped connection as offline', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'ledger.contribute_enabled': true});
    final _SpyClient client = _SpyClient((_) async => throw http.ClientException('no route'));

    expect(await _uploader(client).send(_sample), ContributionResult.offline);
  });
}
