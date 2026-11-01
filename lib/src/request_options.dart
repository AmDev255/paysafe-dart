import 'dart:math';

import 'errors.dart';
import 'validate.dart';

/// Per-call options.
class RequestOptions {
  RequestOptions({
    this.idempotencyKey,
    this.requestId,
    this.timeout,
    this.maxRetries,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers) {
    if (idempotencyKey != null) validateIdempotencyKey(idempotencyKey!);
    if (requestId != null) validateRequestId(requestId!);
    if (maxRetries != null && maxRetries! < 0) {
      throw InvalidRequestException('maxRetries must be zero or more');
    }
    if (timeout != null && timeout! <= Duration.zero) {
      throw InvalidRequestException('timeout must be positive');
    }
    validateHeaders(headers);
  }

  /// Required for payments, refunds and transfers; generated when omitted.
  final String? idempotencyKey;

  /// Your own correlation id, 8 to 64 characters of A-Z a-z 0-9 . _ -
  final String? requestId;

  /// Per-attempt timeout for this call.
  final Duration? timeout;

  /// Retries after the first attempt for this call only.
  final int? maxRetries;

  /// Extra headers. Authorization, Host and framing headers cannot be set.
  final Map<String, String> headers;

  static RequestOptions withIdempotencyKey(String key) =>
      RequestOptions(idempotencyKey: key);

  static RequestOptions orDefault(RequestOptions? options) =>
      options ?? RequestOptions();

  static RequestOptions withKey(RequestOptions? options) =>
      orDefault(options).withGeneratedKeyIfMissing();

  RequestOptions withGeneratedKeyIfMissing() => idempotencyKey != null
      ? this
      : RequestOptions(
          idempotencyKey: generateUuid(),
          requestId: requestId,
          timeout: timeout,
          maxRetries: maxRetries,
          headers: headers,
        );
}

/// A random UUID v4.
String generateUuid() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// One HTTP attempt. Never contains the key or any body. `status` is null when no response arrived.
class LogRecord {
  const LogRecord({
    required this.method,
    required this.path,
    required this.status,
    required this.attempt,
    required this.duration,
    required this.requestId,
    required this.error,
  });

  final String method;
  final String path;
  final int? status;
  final int attempt;
  final Duration duration;
  final String? requestId;
  final String? error;

  @override
  String toString() =>
      'LogRecord($method $path status=$status attempt=$attempt ${duration.inMilliseconds}ms'
      ' requestId=$requestId error=$error)';
}

/// Options for the waitForTerminal helpers.
class WaitOptions {
  const WaitOptions(
      {this.interval, this.timeout, this.onUpdate, this.shouldStop});

  /// Time between polls (minimum 500 ms).
  final Duration? interval;

  /// Give up after this much waiting.
  final Duration? timeout;

  /// Called with the status whenever it changes.
  final void Function(String status)? onUpdate;

  /// Return true to stop early.
  final bool Function()? shouldStop;
}
