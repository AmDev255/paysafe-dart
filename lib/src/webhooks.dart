import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'models.dart';

/// Webhook signature verification: HMAC-SHA256 over "timestamp.rawBody", constant-time comparison.
class Webhooks {
  Webhooks._();

  static const signatureHeader = 'PaySafe-Signature';
  static const defaultToleranceSeconds = 300;
  static const _maxHeaderBytes = 4096;
  static const _maxPayloadBytes = 1024 * 1024;

  /// Builds a PaySafe-Signature value. Intended for tests.
  static String sign(String secret, List<int> payload, int timestamp) =>
      't=$timestamp,v1=${_hmacHex(secret, timestamp, payload)}';

  /// True when the raw payload was signed by one of the [secrets] within the tolerance window. Never throws.
  static bool verifySignature(
    Object secrets,
    List<int> payload,
    String? header, {
    int tolerance = defaultToleranceSeconds,
    int? now,
  }) {
    try {
      _check(_secretList(secrets), payload, header, tolerance, now);
      return true;
    } on SignatureVerificationException {
      return false;
    }
  }

  /// Verifies the delivery and returns the typed [Event]. Throws [SignatureVerificationException] with a reason.
  static Event constructEvent(
    Object secrets,
    List<int> payload,
    String? header, {
    int tolerance = defaultToleranceSeconds,
    int? now,
  }) {
    _check(_secretList(secrets), payload, header, tolerance, now);
    Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(payload));
    } on FormatException {
      parsed = null;
    }
    if (parsed is! Map<String, dynamic> ||
        parsed['id'] is! String ||
        parsed['type'] is! String) {
      throw SignatureVerificationException(
          SignatureVerificationException.invalidPayload,
          'Webhook payload is not an event object');
    }
    return Event(parsed);
  }

  static List<String> _secretList(Object secrets) {
    if (secrets is String) return [secrets];
    if (secrets is List<String>) return secrets;
    throw ArgumentError('secrets must be a String or a List<String>');
  }

  static void _check(List<String> secrets, List<int> payload, String? header,
      int tolerance, int? now) {
    if (header == null || header.trim().isEmpty) {
      throw SignatureVerificationException(
          SignatureVerificationException.missingHeader,
          'PaySafe-Signature header is missing');
    }
    if (header.length > _maxHeaderBytes || payload.length > _maxPayloadBytes) {
      throw SignatureVerificationException(
          SignatureVerificationException.malformedHeader,
          'Webhook header or payload is too large');
    }
    String? timestamp;
    final signatures = <String>[];
    for (final part in header.split(',')) {
      final eq = part.indexOf('=');
      if (eq < 0) continue;
      final key = part.substring(0, eq).trim();
      final value = part.substring(eq + 1).trim();
      if (key == 't') timestamp = value;
      if (key == 'v1') signatures.add(value.toLowerCase());
    }
    final t = timestamp == null || !RegExp(r'^\d+$').hasMatch(timestamp)
        ? null
        : int.tryParse(timestamp);
    if (t == null || signatures.isEmpty) {
      throw SignatureVerificationException(
          SignatureVerificationException.malformedHeader,
          'PaySafe-Signature header is malformed');
    }
    final current =
        now ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    if ((current - t).abs() > tolerance) {
      throw SignatureVerificationException(
          SignatureVerificationException.timestampOutsideTolerance,
          'Webhook timestamp is outside the tolerance window');
    }
    for (final secret in secrets) {
      final expected = _hmacHex(secret, t, payload);
      for (final signature in signatures) {
        if (_constantTimeEquals(expected, signature)) return;
      }
    }
    throw SignatureVerificationException(
        SignatureVerificationException.signatureMismatch,
        'Webhook signature does not match');
  }

  static String _hmacHex(String secret, int timestamp, List<int> payload) {
    final mac = Hmac(sha256, utf8.encode(secret));
    return mac.convert([...utf8.encode('$timestamp.'), ...payload]).toString();
  }

  static bool _constantTimeEquals(String a, String b) {
    final x = a.codeUnits;
    final y = b.codeUnits;
    if (x.length != y.length) return false;
    var diff = 0;
    for (var i = 0; i < x.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}
