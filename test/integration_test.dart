import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:test/test.dart';

// Runs against the real sandbox when PAYSAFE_SECRET_KEY holds a paysafe_test_ key. Never uses a live key.
void main() {
  final key = Platform.environment['PAYSAFE_SECRET_KEY'];
  final skip = key == null || !key.startsWith('paysafe_test_')
      ? 'PAYSAFE_SECRET_KEY with a paysafe_test_ key is not set'
      : null;

  PaySafeClient newClient() {
    final client = PaySafeClient();
    expect(client.environment, PaySafeEnvironment.test);
    return client;
  }

  String token() =>
      Random.secure().nextInt(1 << 32).toRadixString(16).padLeft(8, '0');

  test('balance and transactions', () async {
    final client = newClient();
    final b = await client.balance.get();
    expect(b.livemode, isFalse);
    expect(b.lastResponse!.requestId, isNotNull);
    expect(
        (await client.balance.transactions(const ListParams(limit: 5))).length,
        lessThanOrEqualTo(5));
    client.close();
  }, skip: skip);

  test('payment lifecycle', () async {
    final client = newClient();
    final p = await client.payments.create(CreatePaymentParams(
        amount: 10000,
        customer: const CustomerParams(phone: '+255712340000'),
        reference: 'sdk-dart-${token()}'));
    expect(p.lastResponse!.status, 202);
    final done = await client.payments.waitForTerminal(
        p.id, const WaitOptions(timeout: Duration(seconds: 60)));
    expect(done.status, 'succeeded');
    final declined = await client.payments.create(const CreatePaymentParams(
        amount: 10000, customer: CustomerParams(phone: '+255712341111')));
    final failed = await client.payments.waitForTerminal(
        declined.id, const WaitOptions(timeout: Duration(seconds: 60)));
    expect(failed.status, 'failed');
    expect(failed.failure!.code, 'customer_declined');
    expect(await client.payments.list(const ListPaymentsParams(limit: 3)),
        isNotEmpty);
    expect((await client.payments.get(p.id)).id, p.id);
    await expectLater(
        client.payments.cancel(p.id), throwsA(isA<InvalidStateException>()));
    client.close();
  }, skip: skip);

  test('validation and not found', () async {
    final client = newClient();
    await expectLater(
        client.request('POST', '/v1/payments',
            body: utf8.encode('{"amount":5}'),
            options:
                RequestOptions.withIdempotencyKey('sdk-dart-bad-${token()}')),
        throwsA(isA<ValidationException>()));
    await expectLater(client.payments.get('pay_00000000000000000000000000'),
        throwsA(isA<NotFoundException>()));
    client.close();
  }, skip: skip);

  test('webhook endpoint round trip', () async {
    final client = newClient();
    final created = await client.webhookEndpoints.create(
        CreateWebhookEndpointParams(
            url: 'https://example.com/paysafe/${token()}',
            events: const ['payment.succeeded']));
    expect(created.secret, startsWith('paysafe_webhook_'));
    expect(
        (await client.webhookEndpoints.update(created.id,
                const UpdateWebhookEndpointParams(status: 'DISABLED')))
            .status,
        'DISABLED');
    expect((await client.webhookEndpoints.list()).map((e) => e.id),
        contains(created.id));
    await client.webhookEndpoints.delete(created.id);
    await expectLater(client.webhookEndpoints.get(created.id),
        throwsA(isA<NotFoundException>()));
    client.close();
  }, skip: skip);

  test('events and customers', () async {
    final client = newClient();
    for (final e
        in await client.events.list(const ListEventsParams(limit: 2))) {
      expect((await client.events.get(e.id)).id, e.id);
    }
    for (final c
        in await client.customers.list(const ListCustomersParams(limit: 2))) {
      expect((await client.customers.get(c.id)).id, c.id);
    }
    client.close();
  }, skip: skip);
}
