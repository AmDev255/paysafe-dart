// Request parameters. Null fields are omitted from the JSON.

Map<String, dynamic> _compact(Map<String, dynamic> m) =>
    Map.fromEntries(m.entries.where((e) => e.value != null));

T? _as<T>(Map<String, dynamic> m, String key) =>
    m[key] is T ? m[key] as T : null;

class CustomerParams {
  const CustomerParams({required this.phone, this.name, this.email});

  factory CustomerParams.fromJson(Map<String, dynamic> m) => CustomerParams(
      phone: _as<String>(m, 'phone') ?? '',
      name: _as(m, 'name'),
      email: _as(m, 'email'));

  final String phone;
  final String? name;
  final String? email;

  Map<String, dynamic> toJson() =>
      _compact({'phone': phone, 'name': name, 'email': email});
}

class CreatePaymentParams {
  const CreatePaymentParams({
    required this.amount,
    required this.customer,
    this.currency,
    this.reference,
    this.description,
    this.metadata,
    this.expiresIn,
    this.channel,
  });

  factory CreatePaymentParams.fromJson(Map<String, dynamic> m) =>
      CreatePaymentParams(
        amount: _as<int>(m, 'amount') ?? 0,
        customer: CustomerParams.fromJson(
            _as<Map<String, dynamic>>(m, 'customer') ?? const {}),
        currency: _as(m, 'currency'),
        reference: _as(m, 'reference'),
        description: _as(m, 'description'),
        metadata: _as(m, 'metadata'),
        expiresIn: _as(m, 'expires_in'),
        channel: _as(m, 'channel'),
      );

  final int amount;
  final CustomerParams customer;
  final String? currency;
  final String? reference;
  final String? description;
  final Map<String, dynamic>? metadata;
  final int? expiresIn;

  /// mpesa, tigopesa, airtel or halopesa; inferred from the phone prefix when omitted.
  final String? channel;

  Map<String, dynamic> toJson() => _compact({
        'amount': amount,
        'currency': currency,
        'customer': customer.toJson(),
        'reference': reference,
        'description': description,
        'metadata': metadata,
        'expires_in': expiresIn,
        'channel': channel,
      });
}

class ListPaymentsParams {
  const ListPaymentsParams({
    this.limit,
    this.cursor,
    this.status,
    this.reference,
    this.customerPhone,
    this.createdGte,
    this.createdLte,
  });

  final int? limit;
  final String? cursor;
  final String? status;
  final String? reference;
  final String? customerPhone;
  final String? createdGte;
  final String? createdLte;

  ListPaymentsParams withCursor(String cursor) => ListPaymentsParams(
        limit: limit,
        cursor: cursor,
        status: status,
        reference: reference,
        customerPhone: customerPhone,
        createdGte: createdGte,
        createdLte: createdLte,
      );
}

class CreatePaymentLinkParams {
  const CreatePaymentLinkParams({
    required this.title,
    this.description,
    this.amount,
    this.minAmount,
    this.maxAmount,
    this.currency,
    this.collectName,
    this.collectEmail,
    this.maxPayments,
    this.expiresAt,
    this.successMessage,
    this.redirectUrl,
    this.logo,
    this.accentColor,
  });

  factory CreatePaymentLinkParams.fromJson(Map<String, dynamic> m) =>
      CreatePaymentLinkParams(
        title: _as<String>(m, 'title') ?? '',
        description: _as(m, 'description'),
        amount: _as(m, 'amount'),
        minAmount: _as(m, 'min_amount'),
        maxAmount: _as(m, 'max_amount'),
        currency: _as(m, 'currency'),
        collectName: _as(m, 'collect_name'),
        collectEmail: _as(m, 'collect_email'),
        maxPayments: _as(m, 'max_payments'),
        expiresAt: _as(m, 'expires_at'),
        successMessage: _as(m, 'success_message'),
        redirectUrl: _as(m, 'redirect_url'),
        logo: _as(m, 'logo'),
        accentColor: _as(m, 'accent_color'),
      );

  final String title;
  final String? description;
  final int? amount;
  final int? minAmount;
  final int? maxAmount;
  final String? currency;
  final bool? collectName;
  final bool? collectEmail;
  final int? maxPayments;

  /// RFC 3339 timestamp.
  final String? expiresAt;
  final String? successMessage;
  final String? redirectUrl;
  final String? logo;
  final String? accentColor;

  Map<String, dynamic> toJson() => _compact({
        'title': title,
        'description': description,
        'amount': amount,
        'min_amount': minAmount,
        'max_amount': maxAmount,
        'currency': currency,
        'collect_name': collectName,
        'collect_email': collectEmail,
        'max_payments': maxPayments,
        'expires_at': expiresAt,
        'success_message': successMessage,
        'redirect_url': redirectUrl,
        'logo': logo,
        'accent_color': accentColor,
      });
}

class UpdatePaymentLinkParams {
  const UpdatePaymentLinkParams({
    this.title,
    this.description,
    this.maxPayments,
    this.expiresAt,
    this.status,
    this.successMessage,
    this.redirectUrl,
    this.collectName,
    this.collectEmail,
    this.logo,
    this.accentColor,
  });

  factory UpdatePaymentLinkParams.fromJson(Map<String, dynamic> m) =>
      UpdatePaymentLinkParams(
        title: _as(m, 'title'),
        description: _as(m, 'description'),
        maxPayments: _as(m, 'max_payments'),
        expiresAt: _as(m, 'expires_at'),
        status: _as(m, 'status'),
        successMessage: _as(m, 'success_message'),
        redirectUrl: _as(m, 'redirect_url'),
        collectName: _as(m, 'collect_name'),
        collectEmail: _as(m, 'collect_email'),
        logo: _as(m, 'logo'),
        accentColor: _as(m, 'accent_color'),
      );

  final String? title;
  final String? description;
  final int? maxPayments;
  final String? expiresAt;

  /// active, paused or archived.
  final String? status;
  final String? successMessage;
  final String? redirectUrl;
  final bool? collectName;
  final bool? collectEmail;
  final String? logo;
  final String? accentColor;

  Map<String, dynamic> toJson() => _compact({
        'title': title,
        'description': description,
        'max_payments': maxPayments,
        'expires_at': expiresAt,
        'status': status,
        'success_message': successMessage,
        'redirect_url': redirectUrl,
        'collect_name': collectName,
        'collect_email': collectEmail,
        'logo': logo,
        'accent_color': accentColor,
      });
}

class ListPaymentLinksParams {
  const ListPaymentLinksParams({this.limit, this.cursor, this.status});

  final int? limit;
  final String? cursor;
  final String? status;

  ListPaymentLinksParams withCursor(String cursor) =>
      ListPaymentLinksParams(limit: limit, cursor: cursor, status: status);
}

class Instalment {
  const Instalment({required this.amount, required this.dueAt});

  factory Instalment.fromJson(Map<String, dynamic> m) => Instalment(
      amount: _as<int>(m, 'amount') ?? 0,
      dueAt: _as<String>(m, 'due_at') ?? '');

  final int amount;
  final String dueAt;

  Map<String, dynamic> toJson() => {'amount': amount, 'due_at': dueAt};
}

class CreateControlNumberParams {
  const CreateControlNumberParams({
    required this.payerName,
    required this.title,
    required this.amount,
    this.payerPhone,
    this.payerEmail,
    this.payerReference,
    this.description,
    this.reference,
    this.paymentType,
    this.mode,
    this.currency,
    this.expiresAt,
    this.notes,
    this.instalments,
    this.metadata,
    this.image,
  });

  factory CreateControlNumberParams.fromJson(Map<String, dynamic> m) =>
      CreateControlNumberParams(
        payerName: _as<String>(m, 'payer_name') ?? '',
        title: _as<String>(m, 'title') ?? '',
        amount: _as<int>(m, 'amount') ?? 0,
        payerPhone: _as(m, 'payer_phone'),
        payerEmail: _as(m, 'payer_email'),
        payerReference: _as(m, 'payer_reference'),
        description: _as(m, 'description'),
        reference: _as(m, 'reference'),
        paymentType: _as(m, 'payment_type'),
        mode: _as(m, 'mode'),
        currency: _as(m, 'currency'),
        expiresAt: _as(m, 'expires_at'),
        notes: _as(m, 'notes'),
        instalments: m['instalments'] is List
            ? (m['instalments'] as List)
                .whereType<Map<String, dynamic>>()
                .map(Instalment.fromJson)
                .toList()
            : null,
        metadata: _as(m, 'metadata'),
        image: _as(m, 'image'),
      );

  final String payerName;
  final String title;
  final int amount;
  final String? payerPhone;
  final String? payerEmail;
  final String? payerReference;
  final String? description;
  final String? reference;
  final String? paymentType;

  /// full or instalment.
  final String? mode;
  final String? currency;

  /// RFC 3339 instant or YYYY-MM-DD.
  final String? expiresAt;
  final String? notes;
  final List<Instalment>? instalments;
  final Map<String, dynamic>? metadata;
  final String? image;

  Map<String, dynamic> toJson() => _compact({
        'payer_name': payerName,
        'payer_phone': payerPhone,
        'payer_email': payerEmail,
        'payer_reference': payerReference,
        'title': title,
        'description': description,
        'reference': reference,
        'payment_type': paymentType,
        'mode': mode,
        'amount': amount,
        'currency': currency,
        'expires_at': expiresAt,
        'notes': notes,
        'instalments': instalments?.map((i) => i.toJson()).toList(),
        'metadata': metadata,
        'image': image,
      });
}

class ListControlNumbersParams {
  const ListControlNumbersParams(
      {this.limit,
      this.cursor,
      this.status,
      this.state,
      this.batch,
      this.customer,
      this.q});

  final int? limit;
  final String? cursor;
  final String? status;
  final String? state;
  final String? batch;
  final String? customer;
  final String? q;

  ListControlNumbersParams withCursor(String cursor) =>
      ListControlNumbersParams(
        limit: limit,
        cursor: cursor,
        status: status,
        state: state,
        batch: batch,
        customer: customer,
        q: q,
      );
}

class CreateRefundParams {
  const CreateRefundParams(
      {required this.payment, this.amount, this.reason, this.metadata});

  factory CreateRefundParams.fromJson(Map<String, dynamic> m) =>
      CreateRefundParams(
        payment: _as<String>(m, 'payment') ?? '',
        amount: _as(m, 'amount'),
        reason: _as(m, 'reason'),
        metadata: _as(m, 'metadata'),
      );

  final String payment;

  /// Omit to refund the remaining balance.
  final int? amount;

  /// requested_by_customer, duplicate, fraudulent or other.
  final String? reason;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() => _compact({
        'payment': payment,
        'amount': amount,
        'reason': reason,
        'metadata': metadata
      });
}

class ListRefundsParams {
  const ListRefundsParams({this.limit, this.cursor, this.payment, this.status});

  final int? limit;
  final String? cursor;
  final String? payment;
  final String? status;

  ListRefundsParams withCursor(String cursor) => ListRefundsParams(
      limit: limit, cursor: cursor, payment: payment, status: status);
}

class ListParams {
  const ListParams({this.limit, this.cursor});

  final int? limit;
  final String? cursor;

  ListParams withCursor(String cursor) =>
      ListParams(limit: limit, cursor: cursor);
}

class ListCustomersParams {
  const ListCustomersParams({this.limit, this.cursor, this.search});

  final int? limit;
  final String? cursor;
  final String? search;

  ListCustomersParams withCursor(String cursor) =>
      ListCustomersParams(limit: limit, cursor: cursor, search: search);
}

class CreateTransferParams {
  const CreateTransferParams(
      {required this.to, required this.amount, this.currency, this.note});

  factory CreateTransferParams.fromJson(Map<String, dynamic> m) =>
      CreateTransferParams(
        to: _as<String>(m, 'to') ?? '',
        amount: _as<int>(m, 'amount') ?? 0,
        currency: _as(m, 'currency'),
        note: _as(m, 'note'),
      );

  final String to;
  final int amount;
  final String? currency;
  final String? note;

  Map<String, dynamic> toJson() => _compact(
      {'to': to, 'amount': amount, 'currency': currency, 'note': note});
}

class CreateWebhookEndpointParams {
  const CreateWebhookEndpointParams(
      {required this.url, this.description, this.events});

  factory CreateWebhookEndpointParams.fromJson(Map<String, dynamic> m) =>
      CreateWebhookEndpointParams(
        url: _as<String>(m, 'url') ?? '',
        description: _as(m, 'description'),
        events: m['events'] is List
            ? (m['events'] as List).whereType<String>().toList()
            : null,
      );

  final String url;
  final String? description;
  final List<String>? events;

  Map<String, dynamic> toJson() =>
      _compact({'url': url, 'description': description, 'events': events});
}

class UpdateWebhookEndpointParams {
  const UpdateWebhookEndpointParams(
      {this.url, this.description, this.events, this.status});

  factory UpdateWebhookEndpointParams.fromJson(Map<String, dynamic> m) =>
      UpdateWebhookEndpointParams(
        url: _as(m, 'url'),
        description: _as(m, 'description'),
        events: m['events'] is List
            ? (m['events'] as List).whereType<String>().toList()
            : null,
        status: _as(m, 'status'),
      );

  final String? url;
  final String? description;
  final List<String>? events;

  /// ENABLED or DISABLED.
  final String? status;

  Map<String, dynamic> toJson() => _compact({
        'url': url,
        'description': description,
        'events': events,
        'status': status
      });
}

class ListEventsParams {
  const ListEventsParams(
      {this.limit,
      this.cursor,
      this.type,
      this.from,
      this.to,
      this.resourceId});

  final int? limit;
  final String? cursor;
  final String? type;
  final String? from;
  final String? to;
  final String? resourceId;

  ListEventsParams withCursor(String cursor) => ListEventsParams(
      limit: limit,
      cursor: cursor,
      type: type,
      from: from,
      to: to,
      resourceId: resourceId);
}
