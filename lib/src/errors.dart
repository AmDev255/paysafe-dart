import 'api_response.dart';

/// Base class for every error thrown by this SDK.
class PaySafeException implements Exception {
  PaySafeException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

class ConfigurationException extends PaySafeException {
  ConfigurationException(super.message);
}

/// Thrown before any network call when the request fails local validation.
class InvalidRequestException extends PaySafeException {
  InvalidRequestException(super.message, [this.param]);

  final String? param;
}

/// No HTTP response was received (DNS, TLS, socket errors).
class ApiConnectionException extends PaySafeException {
  ApiConnectionException(super.message);
}

class ApiTimeoutException extends ApiConnectionException {
  ApiTimeoutException(super.message);
}

/// The response body exceeded the SDK's size limit. Never retried.
class ResponseTooLargeException extends ApiConnectionException {
  ResponseTooLargeException() : super('Response body exceeds the 16 MB limit');
}

class PollingTimeoutException extends PaySafeException {
  PollingTimeoutException(super.message, this.lastSeen);

  /// The last object fetched before giving up.
  final Object? lastSeen;
}

class SignatureVerificationException extends PaySafeException {
  SignatureVerificationException(this.reason, super.message);

  static const missingHeader = 'missing_header';
  static const malformedHeader = 'malformed_header';
  static const timestampOutsideTolerance = 'timestamp_outside_tolerance';
  static const signatureMismatch = 'signature_mismatch';
  static const invalidPayload = 'invalid_payload';

  final String reason;
}

/// Any non-2xx response from the API. Subclasses exist for every documented error code.
class ApiException extends PaySafeException {
  ApiException({
    required this.status,
    required this.code,
    required String message,
    this.requestId,
    this.param,
    this.details,
    this.docUrl,
    this.headers = const {},
    this.retryAfter,
    this.rateLimit,
  }) : super(message);

  final int status;
  final String code;
  final String? requestId;
  final String? param;
  final Map<String, dynamic>? details;
  final String? docUrl;
  final Map<String, String> headers;
  final int? retryAfter;
  final RateLimit? rateLimit;

  ApiException._copy(ApiException e)
      : this(
          status: e.status,
          code: e.code,
          message: e.message,
          requestId: e.requestId,
          param: e.param,
          details: e.details,
          docUrl: e.docUrl,
          headers: e.headers,
          retryAfter: e.retryAfter,
          rateLimit: e.rateLimit,
        );

  /// Whether the documented retry policy allows retrying with the same idempotency key.
  bool get isRetryable =>
      status == 429 ||
      status == 503 ||
      code == 'idempotency_in_progress' ||
      (status >= 500 && code != 'provider_error');

  @override
  String toString() =>
      '$code ($status) $message [${requestId ?? 'no request id'}]';
}

class ValidationException extends ApiException {
  ValidationException(super.e) : super._copy();
}

class AuthenticationException extends ApiException {
  AuthenticationException(super.e) : super._copy();
}

class PermissionException extends ApiException {
  PermissionException(super.e) : super._copy();

  bool get isIpNotAllowed =>
      details?['code'] == 'ip_not_allowed' ||
      details?['code'] == 'ip_allowlist_empty';

  String? get observedIp => details?['ip'] as String?;
}

class FeatureDisabledException extends ApiException {
  FeatureDisabledException(super.e) : super._copy();
}

class NotFoundException extends ApiException {
  NotFoundException(super.e) : super._copy();
}

class InsufficientFundsException extends ApiException {
  InsufficientFundsException(super.e) : super._copy();

  int? get available => details?['available'] as int?;

  int? get requested => details?['requested'] as int?;
}

class ConflictException extends ApiException {
  ConflictException(super.e) : super._copy();
}

class IdempotencyConflictException extends ConflictException {
  IdempotencyConflictException(super.e);
}

class IdempotencyInProgressException extends ConflictException {
  IdempotencyInProgressException(super.e);
}

class InvalidStateException extends ConflictException {
  InvalidStateException(super.e);
}

class RateLimitException extends ApiException {
  RateLimitException(super.e) : super._copy();

  String? get scope => details?['scope'] as String?;
}

class ProviderException extends ApiException {
  ProviderException(super.e) : super._copy();
}

class ProviderUnavailableException extends ApiException {
  ProviderUnavailableException(super.e) : super._copy();
}

class ServiceUnavailableException extends ApiException {
  ServiceUnavailableException(super.e) : super._copy();
}

class InternalException extends ApiException {
  InternalException(super.e) : super._copy();
}

/// Picks the exception class for a response.
ApiException mapApiError(ApiResponse response) {
  final root = response.json;
  final envelope = root?['error'];
  var code = 'unknown';
  var message = 'HTTP ${response.status} from the PaySafe API';
  var requestId = response.requestId;
  String? param;
  Map<String, dynamic>? details;
  String? docUrl;
  if (envelope is Map<String, dynamic>) {
    if (envelope['code'] is String) code = envelope['code'] as String;
    if (envelope['message'] is String) message = envelope['message'] as String;
    if (envelope['request_id'] is String) {
      requestId = envelope['request_id'] as String;
    }
    if (envelope['param'] is String) param = envelope['param'] as String;
    if (envelope['details'] is Map<String, dynamic>) {
      details = envelope['details'] as Map<String, dynamic>;
    }
    if (envelope['doc_url'] is String) docUrl = envelope['doc_url'] as String;
  } else if (response.body.isNotEmpty) {
    final raw = response.bodyAsString();
    details = {'raw': raw.length > 4096 ? raw.substring(0, 4096) : raw};
  }
  final base = ApiException(
    status: response.status,
    code: code,
    message: message,
    requestId: requestId,
    param: param,
    details: details,
    docUrl: docUrl,
    headers: response.headers,
    retryAfter: response.retryAfter,
    rateLimit: response.rateLimit,
  );
  final byCode = _byCode[code];
  if (byCode != null) return byCode(base);
  final byStatus = _byStatus[response.status];
  if (byStatus != null) return byStatus(base);
  return response.status >= 500 ? InternalException(base) : base;
}

final Map<String, ApiException Function(ApiException)> _byCode = {
  'validation_error': ValidationException.new,
  'authentication_error': AuthenticationException.new,
  'permission_error': PermissionException.new,
  'feature_disabled': FeatureDisabledException.new,
  'not_found': NotFoundException.new,
  'insufficient_funds': InsufficientFundsException.new,
  'conflict': ConflictException.new,
  'idempotency_conflict': IdempotencyConflictException.new,
  'idempotency_in_progress': IdempotencyInProgressException.new,
  'invalid_state': InvalidStateException.new,
  'rate_limited': RateLimitException.new,
  'provider_error': ProviderException.new,
  'provider_unavailable': ProviderUnavailableException.new,
  'service_unavailable': ServiceUnavailableException.new,
};

final Map<int, ApiException Function(ApiException)> _byStatus = {
  400: ValidationException.new,
  401: AuthenticationException.new,
  402: InsufficientFundsException.new,
  403: PermissionException.new,
  404: NotFoundException.new,
  409: ConflictException.new,
  429: RateLimitException.new,
  503: ServiceUnavailableException.new,
};
