import 'dart:convert';

import 'dart:io' show HttpDate;

/// The X-RateLimit-* headers of a response.
class RateLimit {
  const RateLimit({this.limit, this.remaining, this.reset});

  final int? limit;
  final int? remaining;
  final int? reset;
}

/// The raw outcome of a request. Every model carries the one it came from in `lastResponse`.
class ApiResponse {
  ApiResponse(
      this.status, Map<String, String> headers, this.body, this.idempotencyKey)
      : headers = Map.unmodifiable(headers);

  final int status;

  /// Lower-cased header names.
  final Map<String, String> headers;
  final List<int> body;

  /// The Idempotency-Key that was sent, including generated ones.
  final String? idempotencyKey;

  String? get requestId => headers['x-request-id'];

  RateLimit? get rateLimit {
    final limit = headers['x-ratelimit-limit'];
    final remaining = headers['x-ratelimit-remaining'];
    final reset = headers['x-ratelimit-reset'];
    if (limit == null && remaining == null && reset == null) return null;
    return RateLimit(
      limit: int.tryParse(limit?.trim() ?? ''),
      remaining: int.tryParse(remaining?.trim() ?? ''),
      reset: int.tryParse(reset?.trim() ?? ''),
    );
  }

  bool get idempotentReplayed => headers['idempotent-replayed'] == 'true';

  /// Seconds from Retry-After, or null when absent.
  int? get retryAfter {
    final value = headers['retry-after']?.trim();
    if (value == null || value.isEmpty) return null;
    final seconds = int.tryParse(value);
    if (seconds != null) return seconds;
    try {
      final at = HttpDate.parse(value);
      final diff = at.difference(DateTime.now().toUtc()).inMilliseconds;
      return diff <= 0 ? 0 : (diff / 1000).ceil();
    } on Exception {
      return null;
    }
  }

  String bodyAsString() => utf8.decode(body, allowMalformed: true);

  Map<String, dynamic>? get json {
    if (body.isEmpty) return null;
    try {
      final parsed = jsonDecode(bodyAsString());
      return parsed is Map<String, dynamic> ? parsed : null;
    } on FormatException {
      return null;
    }
  }
}
