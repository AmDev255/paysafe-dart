import 'dart:convert';

import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final v = fixture('webhook-vector');
  final secret = str(v, 'secret')!;
  final body = utf8.encode(str(v, 'body')!);
  final tampered = utf8.encode(str(v, 'tamperedBody')!);
  final header = str(v, 'header')!;
  final now = integer(v, 'nowValid')!;
  final ts = integer(v, 'timestamp')!;
  final legacy = v['legacy'] as Map<String, dynamic>;
  final second = v['secondSecret'] as Map<String, dynamic>;

  test('documented vector verifies', () {
    expect(Webhooks.verifySignature(secret, body, header, now: now), isTrue);
    final legacyHeader = 't=$ts,v1=${legacy['signature']}';
    expect(
        Webhooks.verifySignature(legacy['secret'] as String, body, legacyHeader,
            now: now),
        isTrue);
    expect(Webhooks.verifySignature(secret, body, legacyHeader, now: now),
        isFalse);
  });

  test('rejects bad inputs', () {
    final sig = str(v, 'signature');
    expect(
        Webhooks.verifySignature('paysafe_webhook_test_wrong', body, header,
            now: now),
        isFalse);
    expect(
        Webhooks.verifySignature(secret, tampered, header, now: now), isFalse);
    expect(Webhooks.verifySignature(secret, body, null, now: now), isFalse);
    expect(Webhooks.verifySignature(secret, body, '', now: now), isFalse);
    expect(
        Webhooks.verifySignature(secret, body, 'v1=$sig', now: now), isFalse);
    expect(Webhooks.verifySignature(secret, body, 't=abc,v1=$sig', now: now),
        isFalse);
    expect(Webhooks.verifySignature(secret, body, 't=$ts', now: now), isFalse);
    expect(
        Webhooks.verifySignature(secret, body, header,
            now: integer(v, 'nowExpired')),
        isFalse);
    expect(
        Webhooks.verifySignature(secret, body, header,
            now: integer(v, 'nowFuture')),
        isFalse);
    expect(
        Webhooks.verifySignature(secret, body, header,
            tolerance: 1000, now: integer(v, 'nowExpired')),
        isTrue);
  });

  test('rotation and secret lists', () {
    expect(
        Webhooks.verifySignature(secret, body,
            (v['rotation'] as Map<String, dynamic>)['header'] as String,
            now: now),
        isTrue);
    final secondHeader = 't=$ts,v1=${second['signature']}';
    expect(
        Webhooks.verifySignature(
            [secret, second['secret'] as String], body, secondHeader,
            now: now),
        isTrue);
    expect(Webhooks.verifySignature(secret, body, secondHeader, now: now),
        isFalse);
  });

  test('constructEvent returns a typed event', () {
    final e = Webhooks.constructEvent(secret, body, header, now: now);
    expect(e.id, 'evt_01J7A9R5VKM4N5P6R7S8T9V0B6');
    expect(e.type, 'payment.succeeded');
    expect(e.livemode, isFalse);
    expect(e.payment!.id, 'pay_01J7A9Q0K3M4N5P6R7S8T9V0W1');
    expect(e.payment!.status, 'succeeded');
    expect(e.refund, isNull);
  });

  test('constructEvent throws with a reason and without the secret', () {
    expect(
        () => Webhooks.constructEvent(secret, tampered, header, now: now),
        throwsA(isA<SignatureVerificationException>()
            .having((e) => e.reason, 'reason',
                SignatureVerificationException.signatureMismatch)
            .having((e) => e.message, 'message', isNot(contains(secret)))
            .having((e) => e.message, 'message',
                isNot(contains(str(v, 'signature')!)))));
    expect(
        () => Webhooks.constructEvent(secret, body, header,
            now: integer(v, 'nowExpired')),
        throwsA(isA<SignatureVerificationException>().having(
            (e) => e.reason,
            'reason',
            SignatureVerificationException.timestampOutsideTolerance)));
    final list = utf8.encode('[1,2,3]');
    expect(
        () => Webhooks.constructEvent(
            secret, list, Webhooks.sign(secret, list, ts), now: now),
        throwsA(isA<SignatureVerificationException>().having((e) => e.reason,
            'reason', SignatureVerificationException.invalidPayload)));
    expect(Webhooks.sign(secret, body, ts), header);
  });
}
