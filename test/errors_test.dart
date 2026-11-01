import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final cases = <(int, String, Type, bool)>[
    (400, 'validation_error', ValidationException, false),
    (401, 'authentication_error', AuthenticationException, false),
    (403, 'permission_error', PermissionException, false),
    (403, 'feature_disabled', FeatureDisabledException, false),
    (404, 'not_found', NotFoundException, false),
    (402, 'insufficient_funds', InsufficientFundsException, false),
    (409, 'conflict', ConflictException, false),
    (409, 'idempotency_conflict', IdempotencyConflictException, false),
    (409, 'idempotency_in_progress', IdempotencyInProgressException, true),
    (409, 'invalid_state', InvalidStateException, false),
    (429, 'rate_limited', RateLimitException, true),
    (502, 'provider_error', ProviderException, false),
    (503, 'provider_unavailable', ProviderUnavailableException, true),
    (503, 'service_unavailable', ServiceUnavailableException, true),
    (500, 'internal_error', InternalException, true),
  ];

  test('every documented code maps to its class', () async {
    for (final (status, code, type, retryable) in cases) {
      final h = Harness(maxRetries: 0)
        ..enqueueJson(status, {
          'error': {
            'code': code,
            'message': 'm',
            'request_id': 'req_1',
            'param': 'amount',
            'details': {'scope': 'api:key'},
            'doc_url': 'https://paysafe.co.tz/docs/errors#$code',
          }
        }, {
          'Retry-After': '3'
        });
      try {
        await h.client.balance.get();
        fail('$code did not throw');
      } on ApiException catch (e) {
        expect(e.runtimeType, type, reason: code);
        expect(e.status, status);
        expect(e.code, code);
        expect(e.message, 'm');
        expect(e.requestId, 'req_1');
        expect(e.param, 'amount');
        expect(e.details!['scope'], 'api:key');
        expect(e.retryAfter, 3);
        expect(e.isRetryable, retryable, reason: code);
        expect(e.toString(), contains(code));
      }
    }
  });

  test('unknown code falls back to the status', () async {
    final h = Harness(maxRetries: 0)
      ..enqueueJson(404, {
        'error': {'code': 'brand_new', 'message': 'x', 'request_id': 'r'}
      })
      ..enqueueJson(418, {
        'error': {'code': 'teapot', 'message': 'x', 'request_id': 'r'}
      })
      ..enqueueRaw(500, 'oops', {'X-Request-ID': 'req_h'});
    await expectLater(
        h.client.balance.get(),
        throwsA(isA<NotFoundException>()
            .having((e) => e.code, 'code', 'brand_new')));
    await expectLater(
        h.client.balance.get(),
        throwsA(isA<ApiException>()
            .having((e) => e.runtimeType, 'type', ApiException)));
    await expectLater(
        h.client.balance.get(),
        throwsA(isA<InternalException>()
            .having((e) => e.requestId, 'requestId', 'req_h')
            .having((e) => e.code, 'code', 'unknown')));
  });

  test('helpers on specific errors', () async {
    final h = Harness(maxRetries: 0)
      ..enqueueJson(403, {
        'error': {
          'code': 'permission_error',
          'message': 'x',
          'request_id': 'r',
          'details': {'code': 'ip_not_allowed', 'ip': '2a02::1'}
        }
      })
      ..enqueueJson(402, {
        'error': {
          'code': 'insufficient_funds',
          'message': 'x',
          'request_id': 'r',
          'details': {'available': 10, 'requested': 20}
        }
      });
    await expectLater(
        h.client.balance.get(),
        throwsA(isA<PermissionException>()
            .having((e) => e.isIpNotAllowed, 'isIpNotAllowed', isTrue)
            .having((e) => e.observedIp, 'observedIp', '2a02::1')));
    await expectLater(
        h.client.balance.get(),
        throwsA(isA<InsufficientFundsException>()
            .having((e) => e.available, 'available', 10)
            .having((e) => e.requested, 'requested', 20)));
  });
}
