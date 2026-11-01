import 'api_response.dart';

/// Read-only view of an API object. Typed getters read from [raw]; `toJson` returns the API data unchanged.
class ApiObject {
  ApiObject(this.raw);

  final Map<String, dynamic> raw;
  ApiResponse? lastResponse;

  dynamic operator [](String key) => raw[key];

  Map<String, dynamic> toJson() => raw;

  String str(String key) => raw[key] is String ? raw[key] as String : '';

  String? strOrNull(String key) => raw[key] as String?;

  int integer(String key) => raw[key] is int ? raw[key] as int : 0;

  int? intOrNull(String key) => raw[key] is int ? raw[key] as int : null;

  bool boolean(String key) => raw[key] == true;

  Map<String, dynamic>? mapOrNull(String key) =>
      raw[key] is Map<String, dynamic>
          ? raw[key] as Map<String, dynamic>
          : null;

  List<Map<String, dynamic>> maps(String key) => raw[key] is List
      ? (raw[key] as List).whereType<Map<String, dynamic>>().toList()
      : const [];

  @override
  String toString() =>
      '$runtimeType(${raw['id'] ?? raw['object']}${raw['status'] != null ? ' ${raw['status']}' : ''})';
}

class PaymentCustomer extends ApiObject {
  PaymentCustomer(super.raw);

  String get phone => str('phone');
  String? get name => strOrNull('name');
  String? get email => strOrNull('email');
}

class PaymentFailure extends ApiObject {
  PaymentFailure(super.raw);

  String? get code => strOrNull('code');
  String? get message => strOrNull('message');
}

class Payment extends ApiObject {
  Payment(super.raw);

  static const terminalStatuses = [
    'succeeded',
    'failed',
    'cancelled',
    'expired',
    'partially_refunded',
    'refunded'
  ];
  static const successfulStatuses = [
    'succeeded',
    'partially_refunded',
    'refunded'
  ];

  String get id => str('id');
  String get status => str('status');
  int get amount => integer('amount');
  String get currency => str('currency');
  int get amountRefunded => integer('amount_refunded');
  int? get fee => intOrNull('fee');
  int? get net => intOrNull('net');
  PaymentCustomer? get customer => mapOrNull('customer') == null
      ? null
      : PaymentCustomer(mapOrNull('customer')!);
  String? get channel => strOrNull('channel');
  String? get reference => strOrNull('reference');
  String? get description => strOrNull('description');
  String? get paymentLink => strOrNull('payment_link');
  Map<String, dynamic>? get metadata => mapOrNull('metadata');
  PaymentFailure? get failure => mapOrNull('failure') == null
      ? null
      : PaymentFailure(mapOrNull('failure')!);
  bool get livemode => boolean('livemode');
  String? get expiresAt => strOrNull('expires_at');
  String? get succeededAt => strOrNull('succeeded_at');
  String get createdAt => str('created_at');
  String get updatedAt => str('updated_at');
  bool get isTerminal => terminalStatuses.contains(status);
  bool get isSuccessful => successfulStatuses.contains(status);
}

class PaymentLink extends ApiObject {
  PaymentLink(super.raw);

  String get id => str('id');
  String get url => str('url');
  String get title => str('title');
  String? get description => strOrNull('description');
  String get amountType => str('amount_type');
  int? get amount => intOrNull('amount');
  int? get minAmount => intOrNull('min_amount');
  int? get maxAmount => intOrNull('max_amount');
  String get currency => str('currency');
  bool get collectName => boolean('collect_name');
  bool get collectEmail => boolean('collect_email');
  int? get maxPayments => intOrNull('max_payments');
  int get paidCount => integer('paid_count');
  int get paidAmount => integer('paid_amount');
  String? get expiresAt => strOrNull('expires_at');
  String get status => str('status');
  String get state => str('state');
  String? get successMessage => strOrNull('success_message');
  String? get redirectUrl => strOrNull('redirect_url');
  String? get logoUrl => strOrNull('logo_url');
  String? get accentColor => strOrNull('accent_color');
  bool get livemode => boolean('livemode');
  String get createdAt => str('created_at');
  String get updatedAt => str('updated_at');
}

class ControlNumberPayer extends ApiObject {
  ControlNumberPayer(super.raw);

  String get name => str('name');
  String? get phone => strOrNull('phone');
  String? get email => strOrNull('email');
  String? get reference => strOrNull('reference');
}

class ControlNumberEntry extends ApiObject {
  ControlNumberEntry(super.raw);

  String get id => str('id');
  String get source => str('source');
  String? get payment => strOrNull('payment');
  int get amount => integer('amount');
  String get method => str('method');
  String get paidAt => str('paid_at');
  String get status => str('status');
  String? get receiptNumber => strOrNull('receipt_number');
  String? get note => strOrNull('note');
}

/// A control number; [entries] is only populated by `controlNumbers.get`.
class ControlNumber extends ApiObject {
  ControlNumber(super.raw);

  String get id => str('id');
  String get number => str('number');
  String get formatted => str('formatted');
  String? get batch => strOrNull('batch');
  String? get customer => strOrNull('customer');
  ControlNumberPayer get payer =>
      ControlNumberPayer(mapOrNull('payer') ?? const {});
  String get title => str('title');
  String? get description => strOrNull('description');
  String? get reference => strOrNull('reference');
  String? get paymentType => strOrNull('payment_type');
  String get mode => str('mode');
  int get amount => integer('amount');
  int get paidAmount => integer('paid_amount');
  int get balance => integer('balance');
  int get progressPercent => integer('progress_percent');
  String get currency => str('currency');
  int get paymentCount => integer('payment_count');
  String get status => str('status');
  String get paymentStatus => str('payment_status');
  String? get notes => strOrNull('notes');
  Map<String, dynamic>? get metadata => mapOrNull('metadata');
  String get issuedAt => str('issued_at');
  String? get expiresAt => strOrNull('expires_at');
  String? get paidAt => strOrNull('paid_at');
  String? get cancelledAt => strOrNull('cancelled_at');
  String? get cancelReason => strOrNull('cancel_reason');
  String get payUrl => str('pay_url');
  bool get livemode => boolean('livemode');
  String? get imageUrl => strOrNull('image_url');
  String get createdAt => str('created_at');
  List<ControlNumberEntry> get entries =>
      maps('entries').map(ControlNumberEntry.new).toList();
  bool get isTerminal =>
      const ['paid', 'expired', 'cancelled'].contains(status);
}

class TransferParty extends ApiObject {
  TransferParty(super.raw);

  String? get handle => strOrNull('handle');
  String get name => str('name');
  String get organization => str('organization');
  bool get verified => boolean('verified');
}

class Transfer extends ApiObject {
  Transfer(super.raw);

  String get id => str('id');
  String get direction => str('direction');
  int get amount => integer('amount');
  String get currency => str('currency');
  String? get note => strOrNull('note');
  String get status => str('status');
  TransferParty get from => TransferParty(mapOrNull('from') ?? const {});
  TransferParty get to => TransferParty(mapOrNull('to') ?? const {});
  bool get livemode => boolean('livemode');
  String get createdAt => str('created_at');
  String? get completedAt => strOrNull('completed_at');
  bool get isTerminal =>
      const ['completed', 'rejected', 'reversed'].contains(status);
}

class Refund extends ApiObject {
  Refund(super.raw);

  String get id => str('id');
  String get payment => str('payment');
  int get amount => integer('amount');
  String get currency => str('currency');
  String get status => str('status');
  String? get reason => strOrNull('reason');
  String? get failureReason => strOrNull('failure_reason');
  Map<String, dynamic>? get metadata => mapOrNull('metadata');
  String get createdAt => str('created_at');
  String? get completedAt => strOrNull('completed_at');
  bool get isTerminal =>
      const ['succeeded', 'failed', 'rejected'].contains(status);
  bool get isSuccessful => status == 'succeeded';
}

class Balance extends ApiObject {
  Balance(super.raw);

  bool get livemode => boolean('livemode');

  int availableAmount([String currency = 'TZS']) =>
      _amountFor('available', currency);

  int pendingAmount([String currency = 'TZS']) =>
      _amountFor('pending', currency);

  int _amountFor(String bucket, String currency) {
    for (final m in maps(bucket)) {
      if (m['currency'] == currency && m['amount'] is int) {
        return m['amount'] as int;
      }
    }
    return 0;
  }
}

class Transaction extends ApiObject {
  Transaction(super.raw);

  String get id => str('id');
  String get type => str('type');
  String get direction => str('direction');
  String get bucket => str('bucket');
  int get amount => integer('amount');
  int get balanceAfter => integer('balance_after');
  String get currency => str('currency');
  Map<String, dynamic>? get source => mapOrNull('source');
  String? get description => strOrNull('description');
  String get createdAt => str('created_at');
}

class Customer extends ApiObject {
  Customer(super.raw);

  String get id => str('id');
  String get phone => str('phone');
  String? get name => strOrNull('name');
  String? get email => strOrNull('email');
  int? get totalPaid => intOrNull('total_paid');
  int? get paymentCount => intOrNull('payment_count');
  String? get firstSeenAt => strOrNull('first_seen_at');
  String? get lastSeenAt => strOrNull('last_seen_at');
}

/// A webhook endpoint; [secret] is only present on the create response.
class WebhookEndpoint extends ApiObject {
  WebhookEndpoint(super.raw);

  String get id => str('id');
  bool get livemode => boolean('livemode');
  String get url => str('url');
  String? get description => strOrNull('description');
  List<String> get events => raw['events'] is List
      ? (raw['events'] as List).whereType<String>().toList()
      : const [];
  String get status => str('status');
  int get failureStreak => integer('failure_streak');
  String? get disabledReason => strOrNull('disabled_reason');
  String get createdAt => str('created_at');
  String? get secret => strOrNull('secret');
  bool get isEnabled => status == 'ENABLED';
}

class WebhookDelivery extends ApiObject {
  WebhookDelivery(super.raw);

  String get id => str('id');
  String get endpointId => str('endpoint_id');
  int get attempt => integer('attempt');
  String get status => str('status');
  int? get responseStatus => intOrNull('response_status');
  int? get latencyMs => intOrNull('latency_ms');
  String? get error => strOrNull('error');
  String? get deliveredAt => strOrNull('delivered_at');
}

/// A webhook event; [deliveries] is populated by `events.get`.
class Event extends ApiObject {
  Event(super.raw);

  static const types = [
    'payment.pending', 'payment.processing', 'payment.requires_action',
    'payment.succeeded', 'payment.failed',
    'payment.expired', 'payment.cancelled', //
    'refund.pending', 'refund.succeeded', 'refund.failed', //
    'payout.processing', 'payout.paid', 'payout.failed', //
    'transfer.sent', 'transfer.received', 'transfer.in_review',
    'transfer.rejected', 'transfer.reversed', //
    'control_number.partially_paid', 'control_number.paid',
    'control_number.expired', 'control_number.cancelled',
  ];

  String get id => str('id');
  String get type => str('type');
  String get apiVersion => str('api_version');
  bool get livemode => boolean('livemode');
  String get createdAt => str('created_at');
  List<WebhookDelivery> get deliveries =>
      maps('deliveries').map(WebhookDelivery.new).toList();

  Map<String, dynamic> get dataObject {
    final data = mapOrNull('data');
    return data?['object'] is Map<String, dynamic>
        ? data!['object'] as Map<String, dynamic>
        : const {};
  }

  Payment? get payment =>
      type.startsWith('payment.') ? Payment(dataObject) : null;
  Refund? get refund => type.startsWith('refund.') ? Refund(dataObject) : null;
  Transfer? get transfer =>
      type.startsWith('transfer.') ? Transfer(dataObject) : null;
  ControlNumber? get controlNumber =>
      type.startsWith('control_number.') ? ControlNumber(dataObject) : null;
}
