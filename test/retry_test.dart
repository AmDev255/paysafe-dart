import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:test/test.dart';

import 'support.dart';

final errors = <String, bool Function(Object)>{
  'ApiError': (e) => e is ApiException,
  'ApiConnectionError': (e) => e is ApiConnectionException,
  'IdempotencyConflictError': (e) => e is IdempotencyConflictException,
  'ValidationError': (e) => e is ValidationException,
  'InternalError': (e) => e is InternalException,
  'ProviderError': (e) => e is ProviderException,
};

Future<Object?> call(PaySafeClient c, String op, Map<String, dynamic> f) {
  final minimal = f['minimalBody'] as Map<String, dynamic>?;
  switch (op) {
    case 'getBalance':
      return c.balance.get();
    case 'getPayment':
      return c.payments.get('pay_01J7A9Q0K3M4N5P6R7S8T9V0W1');
    case 'listPayments':
      return c.payments.list();
    case 'createPayment':
      return c.payments.create(CreatePaymentParams.fromJson(minimal!));
    case 'createRefund':
      return c.refunds.create(CreateRefundParams.fromJson(minimal!));
    case 'createWebhookEndpoint':
      return c.webhookEndpoints
          .create(CreateWebhookEndpointParams.fromJson(minimal!));
    default:
      throw StateError('unsupported operation $op');
  }
}

void main() {
  final scenarios = (fixture('retry-scenarios')['scenarios'] as List)
      .cast<Map<String, dynamic>>();

  for (final sc in scenarios) {
    final name = sc['name'] as String;
    test(name, () async {
      final op = sc['request'] as String;
      final f = fixture(op);
      final (code, body, headers) = successOf(f);
      final sequence = (sc['sequence'] as List).cast<Map<String, dynamic>>();
      final hasTimeout = sequence.any((s) => s['timeout'] == true);
      final h = Harness(
          timeout: hasTimeout
              ? const Duration(milliseconds: 300)
              : const Duration(seconds: 30));
      for (final step in sequence) {
        if (step['networkError'] == true) {
          h.enqueueDisconnect();
        } else if (step['timeout'] == true) {
          h.enqueueHang();
        } else if (step.containsKey('rawBody')) {
          h.enqueueRaw(step['status'] as int, step['rawBody'] as String,
              {'Content-Type': 'text/html'});
        } else if ((step['status'] as int) < 300) {
          h.enqueueJson(
              code, body, {...headers, ...headerMap(step['headers'])});
        } else {
          final ec = step['code'] as String? ?? 'internal_error';
          h.enqueueJson(
              step['status'] as int,
              {
                'error': {'code': ec, 'message': ec, 'request_id': 'req_x'}
              },
              headerMap(step['headers']));
        }
      }
      final expectation = sc['expect'] as Map<String, dynamic>;
      Object? result;
      Object? raised;
      try {
        result = await call(h.client, op, f);
      } on PaySafeException catch (e) {
        raised = e;
      }
      final expectedError = expectation['error'] as String?;
      if (expectedError != null) {
        expect(raised, isNotNull, reason: '$name: expected $expectedError');
        expect(errors[expectedError]!(raised!), isTrue,
            reason: '$name: got $raised');
        if (expectation['code'] != null) {
          expect((raised as ApiException).code, expectation['code']);
        }
      } else {
        expect(raised, isNull, reason: '$name: $raised');
      }
      expect(h.requestCount, expectation['attempts'],
          reason: '$name attempt count');
      if (expectation['sameIdempotencyKey'] == true) {
        final keys =
            h.server.requests.map((r) => r.header('Idempotency-Key')).toSet();
        expect(keys, hasLength(1));
        expect(keys.first, isNotEmpty);
      }
      if (expectation['sleptAtLeastMs'] != null) {
        expect(h.totalSleep.inMilliseconds,
            greaterThanOrEqualTo(expectation['sleptAtLeastMs'] as int),
            reason: name);
      }
      if (expectation['idempotentReplayed'] != null) {
        expect((result as Payment).lastResponse!.idempotentReplayed,
            expectation['idempotentReplayed']);
      }
    });
  }

  test('timeout is distinguished', () async {
    final h = Harness(maxRetries: 0, timeout: const Duration(milliseconds: 300))
      ..enqueueHang();
    await expectLater(
        h.client.balance.get(), throwsA(isA<ApiTimeoutException>()));
  });

  test('per-request maxRetries and generated key reuse', () async {
    final h = Harness()
      ..enqueueJson(503, {
        'error': {
          'code': 'service_unavailable',
          'message': 'x',
          'request_id': 'r'
        }
      });
    await expectLater(
        h.client.payments.create(
            const CreatePaymentParams(
                amount: 10000,
                customer: CustomerParams(phone: '+255712340000')),
            RequestOptions(idempotencyKey: 'k-1', maxRetries: 0)),
        throwsA(isA<ServiceUnavailableException>()));
    expect(h.requestCount, 1);
    final (code, body, headers) = successOf(fixture('createPayment'));
    h
      ..enqueueJson(500, {
        'error': {'code': 'internal_error', 'message': 'x', 'request_id': 'r'}
      })
      ..enqueueJson(code, body, headers);
    final p = await h.client.payments.create(const CreatePaymentParams(
        amount: 10000, customer: CustomerParams(phone: '+255712340000')));
    final key = p.lastResponse!.idempotencyKey!;
    expect(key.length, 36);
    expect(h.request(1).header('Idempotency-Key'), key);
    expect(h.request(2).header('Idempotency-Key'), key);
  });
}
