part of 'client.dart';

const _minInterval = Duration(milliseconds: 500);
const _slowAfter = Duration(seconds: 30);
const _slowInterval = Duration(seconds: 5);

String _path(List<String> segments) =>
    '/v1${segments.map((s) => '/${Uri.encodeComponent(s)}').join()}';

T _decode<T extends ApiObject>(
    ApiResponse response, T Function(Map<String, dynamic>) make) {
  final data = response.json;
  if (data == null) {
    throw ApiException(
      status: response.status,
      code: 'invalid_json',
      message: 'The API returned a body this SDK could not parse',
      requestId: response.requestId,
      headers: response.headers,
    );
  }
  return make(data)..lastResponse = response;
}

List<int> _encode(Map<String, dynamic> body) => utf8.encode(jsonEncode(body));

Map<String, String?> _query(int? limit, String? cursor,
    [Map<String, String?> extra = const {}]) {
  validateLimit(limit);
  validateCursor(cursor);
  final q = <String, String?>{};
  if (limit != null) q['limit'] = '$limit';
  if (cursor != null) q['cursor'] = cursor;
  for (final e in extra.entries) {
    if (e.value != null && e.value!.isNotEmpty) q[e.key] = e.value;
  }
  return q;
}

Future<T> _poll<T extends ApiObject>(
  PaySafeClient client, {
  required Future<T> Function() fetch,
  required String Function(T) status,
  required bool Function(T) terminal,
  required Duration defaultInterval,
  required Duration defaultTimeout,
  required String what,
  WaitOptions? options,
}) async {
  final o = options ?? const WaitOptions();
  var interval = o.interval ?? defaultInterval;
  if (interval < _minInterval) interval = _minInterval;
  final timeout = o.timeout ?? defaultTimeout;
  var waited = Duration.zero;
  String? last;
  var first = true;
  while (true) {
    final obj = await fetch();
    final s = status(obj);
    if (o.onUpdate != null && (first || s != last)) o.onUpdate!(s);
    first = false;
    last = s;
    if (terminal(obj)) return obj;
    if (o.shouldStop?.call() == true) {
      throw PollingTimeoutException('Polling for $what was cancelled', obj);
    }
    if (waited >= timeout) {
      throw PollingTimeoutException(
          '$what did not reach a terminal state within ${timeout.inSeconds} s',
          obj);
    }
    var delay = interval;
    if (waited >= _slowAfter && delay < _slowInterval) delay = _slowInterval;
    final remaining = timeout - waited;
    if (delay > remaining) delay = remaining;
    await client._pause(delay);
    waited += delay;
  }
}

class PaymentsResource {
  PaymentsResource._(this._client);

  static const minAmount = 1000;
  static const maxAmount = 10000000;
  static const channels = ['mpesa', 'tigopesa', 'airtel', 'halopesa'];
  static const statuses = [
    'created', 'pending', 'processing', 'requires_action', 'succeeded',
    'failed', 'cancelled', 'expired', //
    'partially_refunded', 'refunded',
  ];

  final PaySafeClient _client;

  /// Starts a mobile-money charge (202 Accepted). An Idempotency-Key is generated when [options] has none;
  /// read it from `payment.lastResponse?.idempotencyKey` and persist it before retrying yourself.
  Future<Payment> create(CreatePaymentParams params,
      [RequestOptions? options]) async {
    validateAmount(params.amount, minAmount, maxAmount, 'amount');
    validatePhone(params.customer.phone, 'customer.phone');
    validateString(params.customer.name, 'customer.name', 1, 100);
    validateString(params.customer.email, 'customer.email', 3, 255);
    validateEnum(params.currency, 'currency', const ['TZS']);
    validateEnum(params.channel, 'channel', channels);
    validateString(params.reference, 'reference', 1, 120);
    validateString(params.description, 'description', 1, 255);
    validateMetadata(params.metadata);
    if (params.expiresIn != null) {
      validateAmount(params.expiresIn!, 60, 900, 'expires_in');
    }
    final response = await _client._send('POST', _path(['payments']), const {},
        _encode(params.toJson()), RequestOptions.withKey(options));
    return _decode(response, Payment.new);
  }

  Future<Page<Payment>> list(
      [ListPaymentsParams params = const ListPaymentsParams(),
      RequestOptions? options]) async {
    validateEnum(params.status, 'status', statuses);
    final q = _query(params.limit, params.cursor, {
      'status': params.status,
      'reference': params.reference,
      'customer_phone': params.customerPhone,
      'created_gte': params.createdGte,
      'created_lte': params.createdLte,
    });
    final response =
        await _client._send('GET', _path(['payments']), q, null, options);
    return Page._fromResponse(response, Payment.new,
        (cursor) => list(params.withCursor(cursor), options));
  }

  Future<Payment> get(String id, [RequestOptions? options]) async => _decode(
      await _client._send(
          'GET', _path(['payments', validateId(id)]), const {}, null, options),
      Payment.new);

  /// Only payments in created or pending can be cancelled. The API requires an Idempotency-Key here.
  Future<Payment> cancel(String id,
      {String? reason, RequestOptions? options}) async {
    validateString(reason, 'reason', 0, 255);
    final body = reason == null
        ? <String, dynamic>{}
        : <String, dynamic>{'reason': reason};
    final response = await _client._send(
        'POST',
        _path(['payments', validateId(id), 'cancel']),
        const {},
        _encode(body),
        RequestOptions.withKey(options));
    return _decode(response, Payment.new);
  }

  /// Polls [get] until the payment is terminal (default every 2 s, up to 2 min).
  Future<Payment> waitForTerminal(String id, [WaitOptions? options]) {
    validateId(id);
    return _poll<Payment>(
      _client,
      fetch: () => get(id),
      status: (p) => p.status,
      terminal: (p) => p.isTerminal,
      defaultInterval: const Duration(seconds: 2),
      defaultTimeout: const Duration(seconds: 120),
      what: 'payment $id',
      options: options,
    );
  }
}

class PaymentLinksResource {
  PaymentLinksResource._(this._client);

  static const statuses = ['active', 'paused', 'archived'];

  final PaySafeClient _client;

  Future<PaymentLink> create(CreatePaymentLinkParams params,
      [RequestOptions? options]) async {
    validateRequired(params.title, 'title');
    validateString(params.title, 'title', 2, 120);
    validateString(params.description, 'description', 1, 1000);
    validateOptionalAmount(params.amount, PaymentsResource.minAmount,
        PaymentsResource.maxAmount, 'amount');
    validateOptionalAmount(params.minAmount, PaymentsResource.minAmount,
        PaymentsResource.maxAmount, 'min_amount');
    validateOptionalAmount(params.maxAmount, PaymentsResource.minAmount,
        PaymentsResource.maxAmount, 'max_amount');
    validateEnum(params.currency, 'currency', const ['TZS']);
    validateOptionalAmount(params.maxPayments, 1, 1000000, 'max_payments');
    validateDateString(params.expiresAt, 'expires_at');
    validateString(params.successMessage, 'success_message', 1, 255);
    validateUrl(params.redirectUrl, 'redirect_url', 500);
    validateString(params.logo, 'logo', 0, 240);
    validateString(params.accentColor, 'accent_color', 0, 32);
    final response = await _client._send('POST', _path(['payment-links']),
        const {}, _encode(params.toJson()), options);
    return _decode(response, PaymentLink.new);
  }

  Future<Page<PaymentLink>> list(
      [ListPaymentLinksParams params = const ListPaymentLinksParams(),
      RequestOptions? options]) async {
    validateEnum(params.status, 'status', statuses);
    final response = await _client._send(
        'GET',
        _path(['payment-links']),
        _query(params.limit, params.cursor, {'status': params.status}),
        null,
        options);
    return Page._fromResponse(response, PaymentLink.new,
        (cursor) => list(params.withCursor(cursor), options));
  }

  Future<PaymentLink> get(String id, [RequestOptions? options]) async =>
      _decode(
          await _client._send('GET', _path(['payment-links', validateId(id)]),
              const {}, null, options),
          PaymentLink.new);

  /// Pause, resume, archive or edit a link. The amount cannot be changed; archiving is permanent.
  Future<PaymentLink> update(String id, UpdatePaymentLinkParams params,
      [RequestOptions? options]) async {
    validateString(params.title, 'title', 2, 120);
    validateEnum(params.status, 'status', statuses);
    validateString(params.description, 'description', 1, 1000);
    validateOptionalAmount(params.maxPayments, 1, 1000000, 'max_payments');
    validateDateString(params.expiresAt, 'expires_at');
    validateString(params.successMessage, 'success_message', 1, 255);
    validateUrl(params.redirectUrl, 'redirect_url', 500);
    validateString(params.logo, 'logo', 0, 240);
    validateString(params.accentColor, 'accent_color', 0, 32);
    final response = await _client._send(
        'PATCH',
        _path(['payment-links', validateId(id)]),
        const {},
        _encode(params.toJson()),
        options);
    return _decode(response, PaymentLink.new);
  }

  Future<PaymentLink> pause(String id) =>
      update(id, const UpdatePaymentLinkParams(status: 'paused'));

  Future<PaymentLink> resume(String id) =>
      update(id, const UpdatePaymentLinkParams(status: 'active'));

  Future<PaymentLink> archive(String id) =>
      update(id, const UpdatePaymentLinkParams(status: 'archived'));
}

class ControlNumbersResource {
  ControlNumbersResource._(this._client);

  static const maxAmount = 1000000000000;
  static const statuses = ['active', 'paid', 'expired', 'cancelled'];
  static const states = ['unpaid', 'partial', 'paid', 'overdue'];
  static const modes = ['full', 'instalment'];

  final PaySafeClient _client;

  /// Issues a 12-digit pay-by-reference number (201). The number itself is assigned by the server.
  Future<ControlNumber> create(CreateControlNumberParams params,
      [RequestOptions? options]) async {
    validateRequired(params.payerName, 'payer_name');
    validateRequired(params.title, 'title');
    validateString(params.payerName, 'payer_name', 1, 120);
    validateString(params.payerPhone, 'payer_phone', 0, 20);
    validateString(params.payerEmail, 'payer_email', 0, 255);
    validateString(params.payerReference, 'payer_reference', 0, 120);
    validateString(params.title, 'title', 1, 150);
    validateString(params.description, 'description', 0, 500);
    validateString(params.reference, 'reference', 0, 120);
    validateString(params.paymentType, 'payment_type', 0, 60);
    validateString(params.notes, 'notes', 0, 1000);
    validateString(params.image, 'image', 0, 240);
    validateEnum(params.mode, 'mode', modes);
    validateEnum(params.currency, 'currency', const ['TZS']);
    validateAmount(params.amount, 1, maxAmount, 'amount');
    validateMetadata(params.metadata);
    validateDateString(params.expiresAt, 'expires_at');
    final instalments = params.instalments;
    if (instalments != null) {
      if (instalments.isEmpty) {
        throw InvalidRequestException(
            'instalments must be a non-empty list', 'instalments');
      }
      for (var i = 0; i < instalments.length; i++) {
        validateAmount(
            instalments[i].amount, 1, maxAmount, 'instalments[$i].amount');
        validateRequired(instalments[i].dueAt, 'instalments[$i].due_at');
        validateDateString(instalments[i].dueAt, 'instalments[$i].due_at');
      }
    }
    final response = await _client._send('POST', _path(['control-numbers']),
        const {}, _encode(params.toJson()), options);
    return _decode(response, ControlNumber.new);
  }

  Future<Page<ControlNumber>> list(
      [ListControlNumbersParams params = const ListControlNumbersParams(),
      RequestOptions? options]) async {
    validateEnum(params.status, 'status', statuses);
    validateEnum(params.state, 'state', states);
    validateString(params.q, 'q', 0, 80);
    final q = _query(params.limit, params.cursor, {
      'status': params.status,
      'state': params.state,
      'batch': params.batch,
      'customer': params.customer,
      'q': params.q,
    });
    final response = await _client._send(
        'GET', _path(['control-numbers']), q, null, options);
    return Page._fromResponse(response, ControlNumber.new,
        (cursor) => list(params.withCursor(cursor), options));
  }

  /// The number with every payment entry recorded against it.
  Future<ControlNumber> get(String id, [RequestOptions? options]) async =>
      _decode(
          await _client._send('GET', _path(['control-numbers', validateId(id)]),
              const {}, null, options),
          ControlNumber.new);

  /// Only active numbers can be cancelled; the reason (3 to 500 characters) is kept on the number.
  Future<ControlNumber> cancel(String id, String reason,
      [RequestOptions? options]) async {
    validateRequired(reason, 'reason');
    validateString(reason, 'reason', 3, 500);
    final response = await _client._send(
        'POST',
        _path(['control-numbers', validateId(id), 'cancel']),
        const {},
        _encode({'reason': reason}),
        options);
    return _decode(response, ControlNumber.new);
  }
}

class RefundsResource {
  RefundsResource._(this._client);

  static const reasons = [
    'requested_by_customer',
    'duplicate',
    'fraudulent',
    'other'
  ];
  static const statuses = [
    'pending',
    'processing',
    'succeeded',
    'failed',
    'rejected'
  ];

  final PaySafeClient _client;

  /// Refunds a succeeded payment (202 Accepted). Omit amount to refund the remaining balance.
  Future<Refund> create(CreateRefundParams params,
      [RequestOptions? options]) async {
    validateId(params.payment, 'payment');
    validateOptionalAmount(params.amount, 1, 1 << 62, 'amount');
    validateEnum(params.reason, 'reason', reasons);
    validateMetadata(params.metadata);
    final response = await _client._send('POST', _path(['refunds']), const {},
        _encode(params.toJson()), RequestOptions.withKey(options));
    return _decode(response, Refund.new);
  }

  Future<Page<Refund>> list(
      [ListRefundsParams params = const ListRefundsParams(),
      RequestOptions? options]) async {
    validateEnum(params.status, 'status', statuses);
    if (params.payment != null) validateId(params.payment, 'payment');
    final response = await _client._send(
        'GET',
        _path(['refunds']),
        _query(params.limit, params.cursor,
            {'payment': params.payment, 'status': params.status}),
        null,
        options);
    return Page._fromResponse(response, Refund.new,
        (cursor) => list(params.withCursor(cursor), options));
  }

  Future<Refund> get(String id, [RequestOptions? options]) async => _decode(
      await _client._send(
          'GET', _path(['refunds', validateId(id)]), const {}, null, options),
      Refund.new);

  Future<Refund> waitForTerminal(String id, [WaitOptions? options]) {
    validateId(id);
    return _poll<Refund>(
      _client,
      fetch: () => get(id),
      status: (r) => r.status,
      terminal: (r) => r.isTerminal,
      defaultInterval: const Duration(seconds: 1),
      defaultTimeout: const Duration(seconds: 60),
      what: 'refund $id',
      options: options,
    );
  }
}

class BalanceResource {
  BalanceResource._(this._client);

  final PaySafeClient _client;

  Future<Balance> get([RequestOptions? options]) async => _decode(
      await _client._send('GET', _path(['balance']), const {}, null, options),
      Balance.new);

  /// Ledger entries, newest first.
  Future<Page<Transaction>> transactions(
      [ListParams params = const ListParams(), RequestOptions? options]) async {
    final response = await _client._send('GET', _path(['transactions']),
        _query(params.limit, params.cursor), null, options);
    return Page._fromResponse(response, Transaction.new,
        (cursor) => transactions(params.withCursor(cursor), options));
  }
}

class CustomersResource {
  CustomersResource._(this._client);

  final PaySafeClient _client;

  Future<Page<Customer>> list(
      [ListCustomersParams params = const ListCustomersParams(),
      RequestOptions? options]) async {
    validateString(params.search, 'search', 0, 120);
    final response = await _client._send(
        'GET',
        _path(['customers']),
        _query(params.limit, params.cursor, {'search': params.search}),
        null,
        options);
    return Page._fromResponse(response, Customer.new,
        (cursor) => list(params.withCursor(cursor), options));
  }

  Future<Customer> get(String id, [RequestOptions? options]) async => _decode(
      await _client._send(
          'GET', _path(['customers', validateId(id)]), const {}, null, options),
      Customer.new);
}

class TransfersResource {
  TransfersResource._(this._client);

  final PaySafeClient _client;

  /// Moves money from this project's available balance to another PaySafe project (201).
  Future<Transfer> create(CreateTransferParams params,
      [RequestOptions? options]) async {
    validateRequired(params.to, 'to');
    validateString(params.to, 'to', 3, 31);
    validateAmount(params.amount, 1, 1 << 62, 'amount');
    validateEnum(params.currency, 'currency', const ['TZS']);
    validateString(params.note, 'note', 0, 140);
    final response = await _client._send('POST', _path(['transfers']), const {},
        _encode(params.toJson()), RequestOptions.withKey(options));
    return _decode(response, Transfer.new);
  }

  Future<Page<Transfer>> list(
      [ListParams params = const ListParams(), RequestOptions? options]) async {
    final response = await _client._send('GET', _path(['transfers']),
        _query(params.limit, params.cursor), null, options);
    return Page._fromResponse(response, Transfer.new,
        (cursor) => list(params.withCursor(cursor), options));
  }

  Future<Transfer> get(String id, [RequestOptions? options]) async => _decode(
      await _client._send(
          'GET', _path(['transfers', validateId(id)]), const {}, null, options),
      Transfer.new);

  Future<Transfer> waitForTerminal(String id, [WaitOptions? options]) {
    validateId(id);
    return _poll<Transfer>(
      _client,
      fetch: () => get(id),
      status: (t) => t.status,
      terminal: (t) => t.isTerminal,
      defaultInterval: const Duration(seconds: 2),
      defaultTimeout: const Duration(seconds: 120),
      what: 'transfer $id',
      options: options,
    );
  }
}

class WebhookEndpointsResource {
  WebhookEndpointsResource._(this._client);

  final PaySafeClient _client;

  /// Every endpoint of the project; the API does not paginate this resource.
  Future<List<WebhookEndpoint>> list([RequestOptions? options]) async {
    final response = await _client._send(
        'GET', _path(['webhook-endpoints']), const {}, null, options);
    final data = response.json?['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map((e) => WebhookEndpoint(e)..lastResponse = response)
        .toList();
  }

  /// Registers an endpoint. The signing secret is only returned here; store it immediately.
  Future<WebhookEndpoint> create(CreateWebhookEndpointParams params,
      [RequestOptions? options]) async {
    validateRequired(params.url, 'url');
    validateUrl(params.url, 'url', 500);
    validateString(params.description, 'description', 0, 255);
    _validateEvents(params.events);
    final response = await _client._send('POST', _path(['webhook-endpoints']),
        const {}, _encode(params.toJson()), options);
    return _decode(response, WebhookEndpoint.new);
  }

  Future<WebhookEndpoint> get(String id, [RequestOptions? options]) async =>
      _decode(
          await _client._send(
              'GET',
              _path(['webhook-endpoints', validateId(id)]),
              const {},
              null,
              options),
          WebhookEndpoint.new);

  Future<WebhookEndpoint> update(String id, UpdateWebhookEndpointParams params,
      [RequestOptions? options]) async {
    validateUrl(params.url, 'url', 500);
    validateString(params.description, 'description', 0, 255);
    validateEnum(params.status, 'status', const ['ENABLED', 'DISABLED']);
    _validateEvents(params.events);
    final response = await _client._send(
        'PATCH',
        _path(['webhook-endpoints', validateId(id)]),
        const {},
        _encode(params.toJson()),
        options);
    return _decode(response, WebhookEndpoint.new);
  }

  Future<void> delete(String id, [RequestOptions? options]) async {
    await _client._send('DELETE', _path(['webhook-endpoints', validateId(id)]),
        const {}, null, options);
  }

  void _validateEvents(List<String>? events) {
    if (events == null) return;
    if (events.isEmpty) {
      throw InvalidRequestException(
          'events must be a non-empty list of event types or ["*"]', 'events');
    }
    for (final e in events) {
      if (e != '*' && !Event.types.contains(e)) {
        throw InvalidRequestException('Unknown event type $e', 'events');
      }
    }
  }
}

class EventsResource {
  EventsResource._(this._client);

  final PaySafeClient _client;

  Future<Page<Event>> list(
      [ListEventsParams params = const ListEventsParams(),
      RequestOptions? options]) async {
    validateEnum(params.type, 'type', Event.types);
    validateDateString(params.from, 'from');
    validateDateString(params.to, 'to');
    if (params.resourceId != null) validateId(params.resourceId, 'resourceId');
    final q = _query(params.limit, params.cursor, {
      'type': params.type,
      'from': params.from,
      'to': params.to,
      'resourceId': params.resourceId,
    });
    final response =
        await _client._send('GET', _path(['events']), q, null, options);
    return Page._fromResponse(response, Event.new,
        (cursor) => list(params.withCursor(cursor), options));
  }

  /// The event plus every delivery attempt to your endpoints.
  Future<Event> get(String id, [RequestOptions? options]) async => _decode(
      await _client._send(
          'GET', _path(['events', validateId(id)]), const {}, null, options),
      Event.new);
}
