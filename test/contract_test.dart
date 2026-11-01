import 'dart:convert';

import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:test/test.dart';

import 'support.dart';

const id = 'pay_01J7A9Q0K3M4N5P6R7S8T9V0W1';
const key = 'order-8812-attempt-1';
final keyed = RequestOptions.withIdempotencyKey(key);

Map<String, dynamic> q(Map<String, dynamic> f) =>
    f['query'] as Map<String, dynamic>;

Map<String, dynamic> body(Map<String, dynamic> f) =>
    f['body'] as Map<String, dynamic>;

final calls =
    <String, Future<Object?> Function(PaySafeClient, Map<String, dynamic>)>{
  'createPayment': (c, f) =>
      c.payments.create(CreatePaymentParams.fromJson(body(f)), keyed),
  'listPayments': (c, f) => c.payments.list(ListPaymentsParams(
        limit: integer(q(f), 'limit'),
        cursor: str(q(f), 'cursor'),
        status: str(q(f), 'status'),
        reference: str(q(f), 'reference'),
        customerPhone: str(q(f), 'customer_phone'),
        createdGte: str(q(f), 'created_gte'),
        createdLte: str(q(f), 'created_lte'),
      )),
  'getPayment': (c, _) => c.payments.get(id),
  'cancelPayment': (c, f) => c.payments.cancel(id,
      reason: f['body'] == null ? null : str(body(f), 'reason'),
      options: keyed),
  'createPaymentLink': (c, f) =>
      c.paymentLinks.create(CreatePaymentLinkParams.fromJson(body(f))),
  'listPaymentLinks': (c, f) => c.paymentLinks.list(ListPaymentLinksParams(
      limit: integer(q(f), 'limit'),
      cursor: str(q(f), 'cursor'),
      status: str(q(f), 'status'))),
  'getPaymentLink': (c, _) => c.paymentLinks.get(id),
  'updatePaymentLink': (c, f) =>
      c.paymentLinks.update(id, UpdatePaymentLinkParams.fromJson(body(f))),
  'createControlNumber': (c, f) =>
      c.controlNumbers.create(CreateControlNumberParams.fromJson(body(f))),
  'listControlNumbers': (c, f) =>
      c.controlNumbers.list(ListControlNumbersParams(
        limit: integer(q(f), 'limit'),
        cursor: str(q(f), 'cursor'),
        status: str(q(f), 'status'),
        state: str(q(f), 'state'),
        batch: str(q(f), 'batch'),
        customer: str(q(f), 'customer'),
        q: str(q(f), 'q'),
      )),
  'getControlNumber': (c, _) => c.controlNumbers.get(id),
  'cancelControlNumber': (c, f) =>
      c.controlNumbers.cancel(id, str(body(f), 'reason')!),
  'createRefund': (c, f) =>
      c.refunds.create(CreateRefundParams.fromJson(body(f)), keyed),
  'listRefunds': (c, f) => c.refunds.list(ListRefundsParams(
      limit: integer(q(f), 'limit'),
      cursor: str(q(f), 'cursor'),
      payment: str(q(f), 'payment'),
      status: str(q(f), 'status'))),
  'getRefund': (c, _) => c.refunds.get(id),
  'getBalance': (c, _) => c.balance.get(),
  'listTransactions': (c, f) => c.balance.transactions(
      ListParams(limit: integer(q(f), 'limit'), cursor: str(q(f), 'cursor'))),
  'listCustomers': (c, f) => c.customers.list(ListCustomersParams(
      limit: integer(q(f), 'limit'),
      cursor: str(q(f), 'cursor'),
      search: str(q(f), 'search'))),
  'getCustomer': (c, _) => c.customers.get(id),
  'createTransfer': (c, f) =>
      c.transfers.create(CreateTransferParams.fromJson(body(f)), keyed),
  'listTransfers': (c, f) => c.transfers.list(
      ListParams(limit: integer(q(f), 'limit'), cursor: str(q(f), 'cursor'))),
  'getTransfer': (c, _) => c.transfers.get(id),
  'listWebhookEndpoints': (c, _) => c.webhookEndpoints.list(),
  'createWebhookEndpoint': (c, f) =>
      c.webhookEndpoints.create(CreateWebhookEndpointParams.fromJson(body(f))),
  'getWebhookEndpoint': (c, _) => c.webhookEndpoints.get(id),
  'updateWebhookEndpoint': (c, f) => c.webhookEndpoints
      .update(id, UpdateWebhookEndpointParams.fromJson(body(f))),
  'deleteWebhookEndpoint': (c, _) async {
    await c.webhookEndpoints.delete(id);
    return null;
  },
  'listEvents': (c, f) => c.events.list(ListEventsParams(
        limit: integer(q(f), 'limit'),
        cursor: str(q(f), 'cursor'),
        type: str(q(f), 'type'),
        from: str(q(f), 'from'),
        to: str(q(f), 'to'),
        resourceId: str(q(f), 'resourceId'),
      )),
  'getEvent': (c, _) => c.events.get(id),
};

void main() {
  final operations = (fixture('index')['operations'] as List)
      .map((o) => (o as Map<String, dynamic>)['operationId'] as String)
      .toList();

  test('every operation has a call', () {
    expect(calls.keys.toList()..sort(), operations.toList()..sort());
  });

  for (final op in operations) {
    test('$op: request matches fixture and success parses', () async {
      final f = fixture(op);
      final (code, responseBody, headers) = successOf(f);
      final h = Harness()..enqueueJson(code, responseBody, headers);
      final result = await calls[op]!(h.client, f);
      final req = h.request();
      expect(req.method, f['method']);
      expect(req.url.path, f['resolvedPath']);
      final want = {
        for (final e in q(f).entries)
          if (e.value != null) e.key: '${e.value}'
      };
      expect(req.url.queryParameters, want);
      expect(req.header('Authorization'), 'Bearer $testKey');
      if ((f['headers'] as Map<String, dynamic>)
          .containsKey('Idempotency-Key')) {
        expect(req.header('Idempotency-Key'), key);
      } else {
        expect(req.header('Idempotency-Key'), isNull);
      }
      if (f['body'] != null) {
        expect(req.header('Content-Type'), startsWith('application/json'));
        expect(jsonDecode(req.bodyText), f['body']);
      } else {
        expect(req.body, isEmpty);
      }
      if (responseBody == null) {
        expect(result, isNull);
        return;
      }
      final obj = responseBody as Map<String, dynamic>;
      if (obj['object'] == 'list' && op != 'listWebhookEndpoints') {
        final page = result as Page<ApiObject>;
        expect(page.length, (obj['data'] as List).length);
        expect(page.hasMore, obj['has_more']);
        if (page.isNotEmpty) {
          expect(page.first.lastResponse!.requestId, requestIdValue);
        }
      } else if (op == 'listWebhookEndpoints') {
        expect((result as List<WebhookEndpoint>).length,
            (obj['data'] as List).length);
      } else {
        final model = result as ApiObject;
        expect(model.lastResponse!.requestId, requestIdValue);
        expect(model.toJson(), obj);
      }
    });

    test('$op: every documented error raises the mapped exception', () async {
      final f = fixture(op);
      for (final entry in (f['responses'] as Map<String, dynamic>).entries) {
        if (entry.key.startsWith('2')) continue;
        final status = int.parse(entry.key.split('_').first);
        final response = entry.value as Map<String, dynamic>;
        final h = Harness(maxRetries: 0)
          ..enqueueJson(
              status, response['body'], headerMap(response['headers']));
        try {
          await calls[op]!(h.client, f);
          fail('$op ${entry.key} did not throw');
        } on ApiException catch (e) {
          expect(e.status, status, reason: '$op ${entry.key}');
          expect(e.code, response['code'], reason: '$op ${entry.key}');
          expect(
              e.requestId,
              ((response['body'] as Map<String, dynamic>)['error']
                  as Map<String, dynamic>)['request_id']);
          final retryAfter = headerMap(response['headers'])['Retry-After'];
          if (retryAfter != null) expect(e.retryAfter, int.parse(retryAfter));
          expect(e.headers, isNotEmpty);
        }
      }
    });
  }
}
