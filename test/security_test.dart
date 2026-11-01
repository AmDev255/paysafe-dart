import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('ids that could change the path are rejected', () async {
    for (final id in [
      '../balance',
      'pay_1/cancel',
      'pay_1?limit=1',
      'pay_1#x',
      'pay%2F1',
      'pay 1',
      'pay_1\n',
      '',
      'a' * 65
    ]) {
      final h = Harness();
      await expectLater(
          h.client.payments.get(id), throwsA(isA<InvalidRequestException>()),
          reason: id);
      expect(h.requestCount, 0);
    }
  });

  test('ids and query values are encoded', () async {
    final h = Harness()
      ..enqueueJson(200, successOf(fixture('getPayment')).$2)
      ..enqueueJson(200, successOf(fixture('listPayments')).$2);
    await h.client.payments.get('pay_01J7A9Q0K3M4N5P6R7S8T9V0W1');
    expect(
        h.request(0).url.path, '/v1/payments/pay_01J7A9Q0K3M4N5P6R7S8T9V0W1');
    await h.client.payments
        .list(const ListPaymentsParams(reference: 'order&x=1 #2', limit: 5));
    expect(h.request(1).url.query, 'limit=5&reference=order%26x%3D1%20%232');
  });

  test('header injection and protected headers are rejected', () {
    for (final value in ['abc\r\nX-Injected: 1', 'abc\nX', 'abc\u0000']) {
      expect(() => RequestOptions(headers: {'X-Custom': value}),
          throwsA(isA<InvalidRequestException>()));
    }
    expect(() => RequestOptions(idempotencyKey: 'key\r\nX: 1'),
        throwsA(isA<InvalidRequestException>()));
    expect(() => RequestOptions(requestId: 'bad id'),
        throwsA(isA<InvalidRequestException>()));
    expect(() => RequestOptions(headers: {'authorization': 'Bearer other'}),
        throwsA(isA<InvalidRequestException>()));
  });

  test('unsafe base URLs are rejected', () {
    for (final url in [
      'http://api.paysafe.co.tz',
      'https://user:pass@api.paysafe.co.tz',
      'https://api.paysafe.co.tz/?x=1',
      'https://api.paysafe.co.tz/#x',
      'api.paysafe.co.tz',
      'https://api.paysafe.co.tz\n',
      'ftp://api.paysafe.co.tz',
    ]) {
      expect(
          () => PaySafeClient(
              apiKey: testKey, baseUrl: url, httpClient: FakeClient()),
          throwsA(isA<ConfigurationException>()),
          reason: url);
    }
    PaySafeClient(
        apiKey: testKey,
        baseUrl: 'http://localhost:8088',
        httpClient: FakeClient());
    PaySafeClient(
        apiKey: testKey,
        baseUrl: 'http://api.internal',
        allowInsecureHttp: true,
        httpClient: FakeClient());
    expect(() => PaySafeClient(apiKey: '$testKey\n'),
        throwsA(isA<ConfigurationException>()));
  });

  test('redirects are never followed', () async {
    final h = Harness()
      ..enqueueRaw(302, '', {'Location': 'https://evil.invalid/steal'});
    await expectLater(
        h.client.balance.get(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'unexpected_redirect')));
    expect(h.requestCount, 1);
    expect(h.request().url.host, 'api.test.invalid');
  });

  test('oversized bodies and metadata are rejected before sending', () async {
    final h = Harness();
    const customer = CustomerParams(phone: '+255712340000');
    await expectLater(
        h.client.payments.create(CreatePaymentParams(
            amount: 10000, customer: customer, metadata: {'big': 'b' * 70000})),
        throwsA(isA<InvalidRequestException>()));
    await expectLater(
        h.client.payments.create(CreatePaymentParams(
            amount: 10000, customer: customer, metadata: {'x': 'y' * 9000})),
        throwsA(isA<InvalidRequestException>()));
    expect(h.requestCount, 0);
  });

  test('amounts, phones and enums are validated', () async {
    final h = Harness();
    for (final amount in [0, 999, 10000001, -5]) {
      await expectLater(
          h.client.payments.create(CreatePaymentParams(
              amount: amount,
              customer: const CustomerParams(phone: '+255712340000'))),
          throwsA(isA<InvalidRequestException>()
              .having((e) => e.param, 'param', 'amount')));
    }
    for (final phone in [
      '0712340000',
      '+25571234000',
      '+255 712 340 000',
      '+1255712340000',
      '+255712340000\n'
    ]) {
      await expectLater(
          h.client.payments.create(CreatePaymentParams(
              amount: 10000, customer: CustomerParams(phone: phone))),
          throwsA(isA<InvalidRequestException>()
              .having((e) => e.param, 'param', 'customer.phone')));
    }
    await expectLater(
        h.client.payments.create(const CreatePaymentParams(
            amount: 10000,
            customer: CustomerParams(phone: '+255712340000'),
            channel: 'paypal')),
        throwsA(isA<InvalidRequestException>()));
    await expectLater(
        h.client.webhookEndpoints.create(const CreateWebhookEndpointParams(
            url: 'http://merchant.example/hook')),
        throwsA(isA<InvalidRequestException>()));
    await expectLater(
        h.client.payments.list(ListPaymentsParams(cursor: 'c' * 201)),
        throwsA(isA<InvalidRequestException>()));
    expect(h.requestCount, 0);
  });

  test('oversized responses are refused without retry', () async {
    final h = Harness()
      ..enqueueResponse(http.StreamedResponse(Stream.value([0x78]), 200,
          contentLength: 16777217, headers: const {}));
    await expectLater(
        h.client.balance.get(), throwsA(isA<ResponseTooLargeException>()));
    expect(h.requestCount, 1);
    final streamed = Harness()
      ..enqueueResponse(http.StreamedResponse(
          Stream.fromIterable(
              List.generate(257, (_) => List.filled(65536, 0x78))),
          200,
          headers: const {}));
    await expectLater(streamed.client.balance.get(),
        throwsA(isA<ResponseTooLargeException>()));
    expect(streamed.requestCount, 1);
  });

  test('non-JSON error bodies are truncated and the key never leaks', () async {
    final h = Harness(maxRetries: 0)
      ..enqueueRaw(400, '<b>' * 5000, {'Content-Type': 'text/html'});
    await expectLater(
        h.client.balance.get(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'unknown')
            .having((e) => (e.details!['raw'] as String).length, 'raw length',
                lessThanOrEqualTo(4096))
            .having(
                (e) => e.toString(), 'toString', isNot(contains(testKey)))));
  });

  test('webhook input sizes are bounded', () {
    final v = fixture('webhook-vector');
    final secret = str(v, 'secret')!;
    final now = integer(v, 'nowValid')!;
    expect(
        Webhooks.verifySignature(
            secret, utf8.encode('x' * 1048577), str(v, 'header'),
            now: now),
        isFalse);
    expect(
        Webhooks.verifySignature(
            secret, utf8.encode(str(v, 'body')!), 't' * 5000,
            now: now),
        isFalse);
  });
}
