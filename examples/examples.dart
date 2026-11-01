// Runnable examples: `PAYSAFE_SECRET_KEY=paysafe_test_... dart run examples/examples.dart <name> [args]`.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:paysafe_tz/paysafe_tz.dart';

Future<void> main(List<String> args) async {
  final name = args.isEmpty ? 'auth' : args.first;
  final rest = args.skip(1).toList();
  switch (name) {
    case 'auth':
      await auth();
    case 'create-payment':
      await createPayment(rest.isEmpty ? '+255712340000' : rest.first);
    case 'get-payment':
      await getPayment(rest.first);
    case 'list-payments':
      await listPayments();
    case 'refund':
      await refund(rest.first, rest.length > 1 ? int.parse(rest[1]) : null);
    case 'payment-link':
      await paymentLink();
    case 'control-number':
      await controlNumber();
    case 'transfer':
      await transfer(rest.first);
    case 'webhook-endpoints':
      await webhookEndpoints(rest.first);
    case 'events':
      await events();
    case 'customers-and-balance':
      await customersAndBalance();
    case 'verify-webhook':
      verifyWebhookSelfTest();
    default:
      stderr.writeln('unknown example $name');
      exitCode = 1;
  }
}

String _iso(DateTime t) => '${t.toUtc().toIso8601String().split('.').first}Z';

/// Proves the key works with a read-only call and prints the rate-limit budget.
Future<void> auth() async {
  final client = PaySafeClient();
  try {
    final balance = await client.balance.get();
    print('Environment : ${client.environment}');
    print('Available   : TZS ${balance.availableAmount()}');
    print('Pending     : TZS ${balance.pendingAmount()}');
    print(
        'Rate limit  : ${balance.lastResponse?.rateLimit?.remaining ?? '?'} remaining of '
        '${balance.lastResponse?.rateLimit?.limit ?? '?'}');
    print('Request id  : ${balance.lastResponse?.requestId}');
  } on ApiException catch (e) {
    stderr.writeln('API error $e');
  } finally {
    client.close();
  }
}

/// Creates a TZS 10,000 payment with a persisted idempotency key, then polls until it is terminal.
Future<void> createPayment(String phone) async {
  final orderId = 'order-${Random.secure().nextInt(1 << 32).toRadixString(16)}';
  // Store the key with the order before sending, so a crash and restart reuses it instead of charging twice.
  final keyFile = File('${Directory.systemTemp.path}/paysafe-$orderId.key');
  final key =
      keyFile.existsSync() ? keyFile.readAsStringSync() : '$orderId-attempt-1';
  keyFile.writeAsStringSync(key);
  final client = PaySafeClient();
  try {
    final payment = await client.payments.create(
      CreatePaymentParams(
        amount: 10000,
        currency: 'TZS',
        customer: CustomerParams(phone: phone, name: 'Amina Juma'),
        reference: orderId,
        description: 'Order $orderId',
        metadata: {'order_id': orderId},
      ),
      RequestOptions.withIdempotencyKey(key),
    );
    final replayed =
        payment.lastResponse?.idempotentReplayed == true ? ', replayed' : '';
    print(
        'Created ${payment.id} status=${payment.status} (HTTP ${payment.lastResponse?.status}$replayed)');
    final done = await client.payments.waitForTerminal(
        payment.id, WaitOptions(onUpdate: (s) => print('  $s')));
    print(done.isSuccessful
        ? 'Paid: amount ${done.amount} fee ${done.fee} net ${done.net}'
        : 'Not paid: ${done.status} ${done.failure?.code ?? ''}');
  } on PollingTimeoutException {
    print('Still pending after the timeout; rely on the webhook');
  } on ApiException catch (e) {
    stderr.writeln('API error $e');
  } finally {
    if (keyFile.existsSync()) keyFile.deleteSync();
    client.close();
  }
}

/// Retrieves a payment by id and waits for a terminal state.
Future<void> getPayment(String id) async {
  final client = PaySafeClient();
  try {
    var payment = await client.payments.get(id);
    print(
        '${payment.id} ${payment.status} TZS ${payment.amount} for ${payment.customer?.phone}');
    if (!payment.isTerminal) {
      payment = await client.payments.waitForTerminal(payment.id);
      print('Final status: ${payment.status}');
    }
  } on NotFoundException {
    stderr.writeln('No such payment in this project and environment');
  } finally {
    client.close();
  }
}

/// Lists succeeded payments from the last 7 days, walking every page.
Future<void> listPayments() async {
  final client = PaySafeClient();
  final page = await client.payments.list(ListPaymentsParams(
      status: 'succeeded',
      createdGte: _iso(DateTime.now().subtract(const Duration(days: 7))),
      limit: 50));
  var total = 0;
  await for (final p in page.autoPaging()) {
    print('${p.createdAt} ${p.id} TZS ${p.amount} ${p.reference ?? ''}');
    total += p.amount;
  }
  print('Total: TZS $total');
  client.close();
}

/// Refunds part of a succeeded payment and waits for the result.
Future<void> refund(String paymentId, int? amount) async {
  final client = PaySafeClient();
  try {
    final refund = await client.refunds.create(
        CreateRefundParams(
            payment: paymentId,
            amount: amount,
            reason: 'requested_by_customer'),
        RequestOptions.withIdempotencyKey('refund-$paymentId-1'));
    print('Refund ${refund.id} ${refund.status}');
    final done = await client.refunds.waitForTerminal(refund.id);
    print('Final: ${done.status} ${done.failureReason ?? ''}');
  } on InsufficientFundsException catch (e) {
    print(
        'Not enough available balance: have ${e.available}, need ${e.requested}');
  } on InvalidStateException catch (e) {
    print('Cannot refund: ${e.message}');
  } finally {
    client.close();
  }
}

/// Creates a hosted payment link, lists links, then pauses and archives the new one.
Future<void> paymentLink() async {
  final client = PaySafeClient();
  final link = await client.paymentLinks.create(CreatePaymentLinkParams(
    title: 'Workshop ticket',
    description: 'One seat, Saturday session',
    amount: 25000,
    collectName: true,
    collectEmail: true,
    maxPayments: 50,
    expiresAt: _iso(DateTime.now().add(const Duration(days: 14))),
  ));
  print('Share this: ${link.url} (${link.id})');
  for (final item in await client.paymentLinks
      .list(const ListPaymentLinksParams(status: 'active', limit: 10))) {
    print(
        '${item.id} ${item.title} paid ${item.paidCount}/${item.maxPayments ?? '∞'}');
  }
  final paused = await client.paymentLinks.pause(link.id);
  print('Paused: ${paused.status} state=${paused.state}');
  print('Archived: ${(await client.paymentLinks.archive(link.id)).status}');
  client.close();
}

/// Issues a control number for an invoice, reads it back with its payment entries, then cancels it.
Future<void> controlNumber() async {
  final client = PaySafeClient();
  final number =
      await client.controlNumbers.create(const CreateControlNumberParams(
    payerName: 'Amina Juma',
    payerPhone: '+255712340000',
    payerReference: 'STU-2024-0091',
    title: 'Term 2 school fees',
    reference: 'INV-2026-0042',
    paymentType: 'fees',
    mode: 'instalment',
    amount: 450000,
    expiresAt: '2026-12-31',
    instalments: [
      Instalment(amount: 225000, dueAt: '2026-11-30T00:00:00Z'),
      Instalment(amount: 225000, dueAt: '2026-12-31T00:00:00Z')
    ],
  ));
  print(
      'Control number ${number.formatted} (${number.id}) pay at ${number.payUrl}');
  final detail = await client.controlNumbers.get(number.id);
  print(
      'Balance TZS ${detail.balance}, ${detail.entries.length} entries, ${detail.paymentStatus}');
  for (final e in detail.entries) {
    print('  ${e.paidAt} ${e.status} ${e.amount} via ${e.method}');
  }
  for (final item in await client.controlNumbers
      .list(const ListControlNumbersParams(state: 'unpaid', limit: 5))) {
    print('${item.formatted} ${item.payer.name} owes ${item.balance}');
  }
  print(
      'Cancelled: ${(await client.controlNumbers.cancel(number.id, 'Issued in error during SDK example')).status}');
  client.close();
}

/// Sends TZS 5,000 to another PaySafe project by handle and lists recent transfers.
Future<void> transfer(String to) async {
  final client = PaySafeClient();
  try {
    var t = await client.transfers.create(
        CreateTransferParams(
            to: to, amount: 5000, note: 'Shared delivery cost'),
        RequestOptions.withIdempotencyKey(
            'transfer-$to-${_iso(DateTime.now()).substring(0, 10)}'));
    print(
        'Transfer ${t.id} ${t.status} to ${t.to.name} (${t.to.organization})');
    if (!t.isTerminal) {
      t = await client.transfers.waitForTerminal(t.id);
      print('Review finished: ${t.status}');
    }
  } on InsufficientFundsException catch (e) {
    print('Not enough available balance (have ${e.available})');
  }
  for (final item in await client.transfers.list(const ListParams(limit: 5))) {
    print('${item.createdAt} ${item.direction} ${item.amount} ${item.status}');
  }
  client.close();
}

/// Registers a webhook endpoint, stores its secret, disables it and deletes it again.
Future<void> webhookEndpoints(String url) async {
  final client = PaySafeClient();
  final endpoint = await client.webhookEndpoints.create(
      CreateWebhookEndpointParams(
          url: url,
          description: 'Order fulfilment',
          events: const [
        'payment.succeeded',
        'payment.failed',
        'refund.succeeded'
      ]));
  // The secret is returned once. Put it in your secret store as PAYSAFE_WEBHOOK_SECRET.
  print(
      'Endpoint ${endpoint.id} created; secret starts with ${endpoint.secret?.substring(0, 20)}…');
  for (final item in await client.webhookEndpoints.list()) {
    print('${item.id} ${item.status} ${item.url} streak=${item.failureStreak}');
  }
  print(
      'Now ${(await client.webhookEndpoints.update(endpoint.id, const UpdateWebhookEndpointParams(status: 'DISABLED'))).status}');
  await client.webhookEndpoints.delete(endpoint.id);
  print('Deleted');
  client.close();
}

/// Lists recent payment events and shows the delivery attempts for the newest one.
Future<void> events() async {
  final client = PaySafeClient();
  final events = await client.events.list(ListEventsParams(
      type: 'payment.succeeded',
      from: _iso(DateTime.now().subtract(const Duration(days: 1))),
      limit: 10));
  for (final e in events) {
    print('${e.createdAt} ${e.id} ${e.payment?.id ?? ''}');
  }
  if (events.isNotEmpty) {
    final detail = await client.events.get(events.first.id);
    for (final d in detail.deliveries) {
      print(
          '  attempt ${d.attempt} ${d.status} HTTP ${d.responseStatus ?? '-'} ${d.latencyMs ?? '-'}ms');
    }
  }
  client.close();
}

/// Reads the balance, the latest ledger entries and recent customers.
Future<void> customersAndBalance() async {
  final client = PaySafeClient();
  final balance = await client.balance.get();
  print(
      'Available TZS ${balance.availableAmount()}, pending TZS ${balance.pendingAmount()}');
  for (final tx
      in await client.balance.transactions(const ListParams(limit: 5))) {
    print(
        '${tx.createdAt} ${tx.direction} ${tx.bucket} ${tx.amount} -> ${tx.balanceAfter}');
  }
  for (final c
      in await client.customers.list(const ListCustomersParams(limit: 5))) {
    print(
        '${c.id} ${c.phone} paid ${c.paymentCount ?? 0} times, TZS ${c.totalPaid ?? 0}');
  }
  client.close();
}

/// Verifies the shared webhook test vector; see examples/webhooks/shelf_server.dart for a server.
void verifyWebhookSelfTest() {
  final v =
      jsonDecode(File('tests/fixtures/webhook-vector.json').readAsStringSync())
          as Map<String, dynamic>;
  final event = Webhooks.constructEvent(v['secret'] as String,
      utf8.encode(v['body'] as String), v['header'] as String,
      now: v['nowValid'] as int);
  print('Self-test ok: ${event.type} ${event.payment?.id}');
}
