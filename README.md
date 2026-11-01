# PaySafe Dart SDK

Official Dart library for the [PaySafe](https://paysafe.co.tz) payments API. Accept mobile-money payments in Tanzania, issue refunds, control numbers and payment links, move money between projects, and receive signed webhooks.

Part of the [PaySafe SDK directory](https://github.com/AmDev255/paysafe-sdks). API reference: https://paysafe.co.tz/docs.

## Features

- Every served PaySafe API operation (29 operations, 10 resources) with typed request and response models
- Sandbox and production selected automatically from the key prefix
- Safe retries that honour `Retry-After`, idempotency keys that survive retries, cursor pagination helpers
- Polling helpers that wait for a payment, refund or transfer to reach a terminal state
- Webhook signature verification with secret rotation support and constant-time comparison
- One structured exception per documented error code, every error carries the request id
- Configurable timeouts, base URL, logger and HTTP client

## Installation

```bash
dart pub add paysafe_tz
# Flutter apps: never embed a secret key in the app; call the API from your server
```

## Requirements

Dart 3 or newer. Depends on `http` and `crypto`. Intended for server-side Dart; secret keys must not ship inside Flutter apps.

## Authentication

Create a secret key in the dashboard under API keys. Test keys start with `paysafe_test_`, live keys with `paysafe_live_`. Keep keys on the server; never ship them in browsers or mobile apps. The SDK reads `PAYSAFE_SECRET_KEY` when no key is passed.

## Sandbox setup

Use a `paysafe_test_` key. The sandbox is the same API with a simulated provider; the last four digits of the customer phone choose the outcome (`0000` succeeds, `1111` is declined, `4444` expires, see the [Sandbox guide](https://paysafe.co.tz/docs/sandbox)).

## Production setup

Switch to a `paysafe_live_` key once your organisation is verified. Register a live webhook endpoint and add your server's address to the project's IP allowlist. Nothing else changes.

## Quickstart

```dart
import 'package:paysafe_tz/paysafe_tz.dart';

final client = PaySafeClient(apiKey: Platform.environment['PAYSAFE_SECRET_KEY']); // paysafe_test_… selects the sandbox

final payment = await client.payments.create(
  const CreatePaymentParams(
    amount: 10000, // TZS, integer
    customer: CustomerParams(phone: '+255712340000', name: 'Amina Juma'),
    reference: 'order-8812',
  ),
  RequestOptions.withIdempotencyKey('order-8812-attempt-1'), // persist the key before calling
);
print('${payment.id} ${payment.status}'); // 202 Accepted: still pending

final done = await client.payments.waitForTerminal(payment.id); // or wait for the webhook
if (done.isSuccessful) print('Paid, net TZS ${done.net}');
```

## Supported API resources

| Resource | Operations |
|---|---|
| Payments | create, list, get, cancel, waitForTerminal |
| Payment links | create, list, get, update |
| Control numbers | create, list, get, cancel |
| Refunds | create, list, get, waitForTerminal |
| Balance | get, transactions |
| Customers | list, get |
| Transfers | create, list, get, waitForTerminal |
| Webhook endpoints | list, create, get, update, delete |
| Events | list, get |
| Webhooks | verifySignature, constructEvent |

Planned by PaySafe and not yet served (not included): `ping`, payouts (`createPayout`, `getPayout`), `rotateWebhookEndpointSecret`.

## Usage examples

Runnable programs live in [`examples/examples.dart`](examples/examples.dart) (see [`examples/README.md`](examples/README.md)): authentication, creating and polling a payment, listing with pagination, refunds, payment links, control numbers, transfers, webhook endpoints, events, customers and balance, and a webhook self-test, plus a Shelf server under `examples/webhooks/`.

Every resource exposes async methods (`create`, `list`, `get`, …) that take typed params objects and an optional `RequestOptions`. Lists return a `Page<T>` (an `Iterable`) with `data`, `hasMore`, `nextCursor`, `nextPage()` and `autoPaging()` (a `Stream<T>`).

```dart
// Pagination
await for (final p in (await client.payments.list(const ListPaymentsParams(status: 'succeeded', limit: 100))).autoPaging()) {}

// Refunds
final refund = await client.refunds.create(CreateRefundParams(payment: payment.id, amount: 5000, reason: 'requested_by_customer'));

// Payment links and control numbers
final link = await client.paymentLinks.create(const CreatePaymentLinkParams(title: 'Workshop ticket', amount: 25000));
final number = await client.controlNumbers.create(const CreateControlNumberParams(payerName: 'Amina Juma', title: 'Term 2 fees', amount: 450000));

// Transfers, balance, customers, events
final transfer = await client.transfers.create(const CreateTransferParams(to: 'merchant_shop', amount: 5000));
final balance = await client.balance.get();
final customer = await client.customers.get('cus_…');
final event = await client.events.get('evt_…');

// Webhook endpoints (the secret is returned once)
final endpoint = await client.webhookEndpoints.create(const CreateWebhookEndpointParams(url: 'https://example.com/paysafe', events: ['payment.succeeded']));
```

Responses are typed objects (`Payment`, `Refund`, …) with camelCase getters over the API JSON; `toJson()` and `[]` give the raw data. Every object carries `lastResponse` with `status`, `requestId`, `rateLimit`, `idempotentReplayed` and the `idempotencyKey` that was sent. `RequestOptions` sets `idempotencyKey`, `requestId`, `timeout`, `maxRetries` and extra headers. The client reuses one `http.Client`; pass your own through `httpClient` and call `close()` when done.

Retries: 429 and 503 wait for `Retry-After`; `idempotency_in_progress` waits one second; 5xx and network errors are retried only when the request is idempotent (GET, PATCH, DELETE, or a POST with an idempotency key). The SDK generates a UUID key for `payments.create`, `refunds.create`, `transfers.create` and `payments.cancel` when you do not pass one; pass your own key derived from the order to survive process restarts.

Security: ids, filters, headers and amounts are validated before any request; path and query values are percent-encoded; the base URL must be https (plain http only for localhost or `allowInsecureHttp: true`); redirects are never followed; response bodies are capped at 16 MB; the key never appears in exceptions or logs. This package is for Dart servers: never embed a secret key in a Flutter app.

## Error handling

Every non-2xx response throws a subclass of `ApiException` chosen by the error code, with `status`, `code`, `message`, `requestId`, `param`, `details`, `docUrl`, `retryAfter` and `rateLimit`:

```dart
try {
  await client.payments.cancel(id);
} on ValidationException catch (e) {       // 400: fix the request (e.param names the field)
} on InvalidStateException catch (e) {     // 409: read the object and decide again
} on RateLimitException catch (e) {        // 429 after retries: back off e.retryAfter seconds
} on ApiException catch (e) {              // anything else from the API; e.toString() is "code (status) message [request_id]"
} on ApiConnectionException catch (e) {    // no response at all (DNS, TLS, timeout: ApiTimeoutException)
} on InvalidRequestException catch (e) {   // rejected locally before any request was sent
}
```

Classes: ValidationException, AuthenticationException, PermissionException (`isIpNotAllowed`, `observedIp`), FeatureDisabledException, NotFoundException, InsufficientFundsException (`available`, `requested`), ConflictException, IdempotencyConflictException, IdempotencyInProgressException, InvalidStateException, RateLimitException (`scope`), ProviderException, ProviderUnavailableException, ServiceUnavailableException, InternalException, ApiConnectionException, ApiTimeoutException, ResponseTooLargeException, SignatureVerificationException, PollingTimeoutException, ConfigurationException, InvalidRequestException. Unknown codes map by HTTP status.

## Webhook integration

Verify the raw body before parsing it. `Webhooks.constructEvent` checks the `PaySafe-Signature` header (HMAC-SHA256 over `t.body`, 300 s tolerance, constant-time comparison, several `v1=` values during rotation) and returns a typed `Event`:

```dart
final rawBody = await request.read().fold<List<int>>([], (a, b) => a..addAll(b)); // exact bytes
try {
  final event = Webhooks.constructEvent(secret, rawBody, request.headers['paysafe-signature']);
  if (event.type == 'payment.succeeded') markPaid(event.payment!.reference); // deduplicate on event.id first
} on SignatureVerificationException {
  return Response(400);
}
```

`Webhooks.verifySignature` returns a bool instead of throwing; both accept a `String` or a `List<String>` of secrets and a `tolerance:` argument. `examples/webhooks/shelf_server.dart` shows a Shelf server and `dart run examples/examples.dart verify-webhook` runs the self-test.

## Testing

```bash
dart pub get
dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos && dart test && dart pub publish --dry-run
```

Tests run offline against the fixtures in `tests/fixtures/` that are shared by every PaySafe SDK, with HTTP served by a scripted `http.BaseClient`. The integration tests run only when `PAYSAFE_SECRET_KEY` holds a `paysafe_test_` key (and optionally `PAYSAFE_BASE_URL`); they refuse live keys and use the sandbox phone suffixes documented at https://paysafe.co.tz/docs/sandbox. See `examples/README.md` for the runnable examples.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
