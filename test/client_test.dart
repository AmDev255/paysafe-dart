import 'dart:convert';

import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final balance = successOf(fixture('getBalance')).$2;

  test('environment from key prefix', () {
    expect(PaySafeClient(apiKey: testKey, httpClient: FakeClient()).environment,
        PaySafeEnvironment.test);
    expect(
        PaySafeClient(
                apiKey: 'paysafe_live_9f2Kx7Qm3Rt8Vw2Yz5Ab1Cd4Ef6Gh9Jk',
                httpClient: FakeClient())
            .environment,
        PaySafeEnvironment.live);
    expect(() => PaySafeClient(apiKey: 'sk_test_abc'),
        throwsA(isA<ConfigurationException>()));
  });

  test('standard headers', () async {
    final h = Harness()..enqueueJson(200, balance);
    await h.client.balance.get();
    final req = h.request();
    expect(req.header('Authorization'), 'Bearer $testKey');
    expect(req.header('Accept'), 'application/json');
    expect(req.header('User-Agent'),
        startsWith('paysafe-dart/${PaySafeClient.version}'));
    expect(req.header('Content-Type'), isNull);
    expect(req.url.path, '/v1/balance');
    expect(req.url.hasQuery, isFalse);
  });

  test('api version header', () async {
    final h = Harness(apiVersion: '2026-09-07')..enqueueJson(200, balance);
    await h.client.balance.get();
    expect(h.request().header('PaySafe-Version'), '2026-09-07');
  });

  test('response metadata on models', () async {
    final h = Harness()
      ..enqueueJson(200, balance, {
        'X-RateLimit-Limit': '50',
        'X-RateLimit-Remaining': '49',
        'X-RateLimit-Reset': '1788775205',
      });
    final b = await h.client.balance.get();
    expect(b.lastResponse!.status, 200);
    expect(b.lastResponse!.requestId, requestIdValue);
    expect(b.lastResponse!.rateLimit!.remaining, 49);
    expect(b.lastResponse!.idempotentReplayed, isFalse);
    expect(jsonEncode(b.toJson()), isNot(contains('lastResponse')));
    expect(b.livemode, isFalse);
    expect(b['object'], 'balance');
  });

  test('low-level request', () async {
    final h = Harness()..enqueueJson(200, balance);
    final r = await h.client.request('get', 'v1/balance');
    expect(r.status, 200);
    expect(h.request().url.path, '/v1/balance');
  });

  test('logger records without secrets', () async {
    final records = <LogRecord>[];
    final h = Harness(logger: records.add)..enqueueJson(200, balance);
    await h.client.balance.get();
    expect(records, hasLength(1));
    expect(records.first.method, 'GET');
    expect(records.first.path, '/v1/balance');
    expect(records.first.status, 200);
    expect(records.first.toString(), isNot(contains(testKey)));
    expect(h.client.toString(), isNot(contains(testKey)));
  });
}
