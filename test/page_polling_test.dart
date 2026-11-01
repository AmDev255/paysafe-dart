import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final payment = successOf(fixture('getPayment')).$2 as Map<String, dynamic>;
  Map<String, dynamic> withField(
          Map<String, dynamic> base, String field, String value) =>
      {...base, field: value};
  Map<String, dynamic> list(
          List<Map<String, dynamic>> items, bool hasMore, String? cursor) =>
      {
        'object': 'list',
        'data': items,
        'has_more': hasMore,
        'next_cursor': cursor
      };

  test('auto paging keeps filters', () async {
    final h = Harness()
      ..enqueueJson(
          200,
          list([
            withField(payment, 'id', 'pay_1'),
            withField(payment, 'id', 'pay_2')
          ], true, 'c2'))
      ..enqueueJson(
          200, list([withField(payment, 'id', 'pay_3')], false, null));
    final page = await h.client.payments
        .list(const ListPaymentsParams(status: 'succeeded', limit: 2));
    expect(page.length, 2);
    expect(page.hasMore, isTrue);
    expect(await page.autoPaging().map((p) => p.id).toList(),
        ['pay_1', 'pay_2', 'pay_3']);
    expect(h.requestCount, 2);
    expect(h.request(1).url.query, 'limit=2&cursor=c2&status=succeeded');
  });

  test('last page has no next', () async {
    final h = Harness()..enqueueJson(200, list([], false, null));
    final page = await h.client.customers.list();
    expect(await page.nextPage(), isNull);
    expect(page, isEmpty);
  });

  test('waitForTerminal reports updates', () async {
    final h = Harness();
    for (final s in ['pending', 'processing', 'processing', 'succeeded']) {
      h.enqueueJson(200, withField(payment, 'status', s));
    }
    final seen = <String>[];
    final p = await h.client.payments.waitForTerminal(
        'pay_01J7A9Q0K3M4N5P6R7S8T9V0W1', WaitOptions(onUpdate: seen.add));
    expect(p.status, 'succeeded');
    expect(p.isSuccessful, isTrue);
    expect(seen, ['pending', 'processing', 'succeeded']);
    expect(h.sleeps, [
      const Duration(seconds: 2),
      const Duration(seconds: 2),
      const Duration(seconds: 2)
    ]);
  });

  test('wait times out with the last object', () async {
    final h = Harness();
    for (var i = 0; i < 4; i++) {
      h.enqueueJson(200, withField(payment, 'status', 'processing'));
    }
    await expectLater(
        h.client.payments.waitForTerminal(
            'pay_01J7A9Q0K3M4N5P6R7S8T9V0W1',
            const WaitOptions(
                interval: Duration(seconds: 2), timeout: Duration(seconds: 6))),
        throwsA(isA<PollingTimeoutException>().having(
            (e) => (e.lastSeen as Payment).status, 'lastSeen', 'processing')));
    expect(h.requestCount, 4);
  });

  test('wait can be cancelled', () async {
    final h = Harness()
      ..enqueueJson(
          200,
          withField(successOf(fixture('getRefund')).$2 as Map<String, dynamic>,
              'status', 'pending'));
    await expectLater(
        h.client.refunds.waitForTerminal('rfd_01J7A9Q0K3M4N5P6R7S8T9V0W1',
            WaitOptions(shouldStop: () => true)),
        throwsA(isA<PollingTimeoutException>()));
  });

  test('wait slows down after thirty seconds', () async {
    final h = Harness();
    final transfer =
        successOf(fixture('getTransfer')).$2 as Map<String, dynamic>;
    for (var i = 0; i < 20; i++) {
      h.enqueueJson(200, withField(transfer, 'status', 'in_review'));
    }
    h.enqueueJson(200, withField(transfer, 'status', 'completed'));
    await h.client.transfers.waitForTerminal('trf_01J7A9Q0K3M4N5P6R7S8T9V0W1');
    expect(h.sleeps.first, const Duration(seconds: 2));
    expect(h.sleeps.last, const Duration(seconds: 5));
  });
}
