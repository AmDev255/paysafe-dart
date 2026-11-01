import 'dart:convert';

import 'errors.dart';

const maxBodyBytes = 65536;
const maxMetadataBytes = 8192;

final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final _headerName = RegExp(r'^[A-Za-z0-9-]{1,100}$');
final _requestId = RegExp(r'^[A-Za-z0-9._-]{8,64}$');
final _phone = RegExp(r'^\+255[0-9]{9}$');
final _queryKey = RegExp(r'^[A-Za-z0-9_]{1,40}$');
final _dateTime = RegExp(
    r'^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2}))?$');
final apiKeyPattern = RegExp(r'^[A-Za-z0-9_]+$');
const _protectedHeaders = {
  'authorization',
  'host',
  'content-length',
  'transfer-encoding',
  'connection'
};
const _loopback = {
  'localhost',
  '127.0.0.1',
  '::1',
  '[::1]',
  'host.docker.internal'
};

bool hasControl(String s, bool allowTab) {
  for (final c in s.codeUnits) {
    if (c == 0x7F || (c < 0x20 && !(allowTab && c == 0x09))) return true;
  }
  return false;
}

void validateIdempotencyKey(String key) {
  if (key.isEmpty ||
      key.length > 255 ||
      key.codeUnits.any((c) => c < 0x20 || c > 0x7E)) {
    throw InvalidRequestException(
        'Idempotency-Key must be 1 to 255 printable ASCII characters');
  }
}

void validateRequestId(String value) {
  if (!_requestId.hasMatch(value)) {
    throw InvalidRequestException(
        'X-Request-ID must be 8 to 64 characters of A-Z a-z 0-9 . _ -');
  }
}

/// Identifiers go into URL paths; anything outside the id alphabet is rejected.
String validateId(String? value, [String name = 'id']) {
  if (value == null || !_id.hasMatch(value)) {
    throw InvalidRequestException(
        '$name must be 1 to 64 characters of A-Z a-z 0-9 _ -', name);
  }
  return value;
}

void validateHeaders(Map<String, String> headers) {
  for (final entry in headers.entries) {
    if (!_headerName.hasMatch(entry.key)) {
      throw InvalidRequestException(
          'Header names may only contain letters, digits and dashes');
    }
    if (_protectedHeaders.contains(entry.key.toLowerCase())) {
      throw InvalidRequestException(
          'The ${entry.key} header cannot be overridden');
    }
    if (entry.value.length > 4096 || hasControl(entry.value, true)) {
      throw InvalidRequestException('Header ${entry.key} has an invalid value');
    }
  }
}

void validateRequired(String? value, String field) {
  if (value == null || value.isEmpty) {
    throw InvalidRequestException('$field is required', field);
  }
}

void validatePhone(String? value, String field) {
  if (value == null || !_phone.hasMatch(value)) {
    throw InvalidRequestException(
        '$field must be an E.164 Tanzanian number (+255 followed by nine digits)',
        field);
  }
}

void validateAmount(int value, int min, int max, String field) {
  if (value < min || value > max) {
    throw InvalidRequestException(
        '$field must be an integer between $min and $max', field);
  }
}

void validateOptionalAmount(int? value, int min, int max, String field) {
  if (value != null) validateAmount(value, min, max, field);
}

void validateEnum(String? value, String field, List<String> allowed) {
  if (value != null && !allowed.contains(value)) {
    throw InvalidRequestException(
        '$field must be one of ${allowed.join(', ')}', field);
  }
}

void validateString(String? value, String field, int min, int max) {
  if (value == null) return;
  final n = value.runes.length;
  if (n < min || n > max || hasControl(value, true)) {
    throw InvalidRequestException(
        '$field must be a string of $min to $max characters', field);
  }
}

void validateMetadata(Map<String, dynamic>? value,
    [String field = 'metadata']) {
  if (value == null) return;
  if (utf8.encode(jsonEncode(value)).length > maxMetadataBytes) {
    throw InvalidRequestException(
        '$field must encode to at most $maxMetadataBytes bytes of JSON', field);
  }
}

bool isLoopback(String? host) =>
    host != null && _loopback.contains(host.toLowerCase());

void validateUrl(String? value, String field, int maxLength) {
  if (value == null) return;
  if (value.length > maxLength ||
      value.contains(RegExp(r'\s')) ||
      hasControl(value, false)) {
    throw InvalidRequestException(
        '$field must be a URL of at most $maxLength characters', field);
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw InvalidRequestException('$field must be an absolute URL', field);
  }
  if (uri.scheme != 'https' &&
      !(uri.scheme == 'http' && isLoopback(uri.host))) {
    throw InvalidRequestException('$field must use https', field);
  }
}

void validateLimit(int? limit) {
  if (limit != null && (limit < 1 || limit > 100)) {
    throw InvalidRequestException(
        'limit must be an integer between 1 and 100', 'limit');
  }
}

void validateCursor(String? cursor) {
  if (cursor == null) return;
  if (cursor.isEmpty ||
      cursor.length > 200 ||
      cursor.codeUnits.any((c) => c < 0x21 || c > 0x7E)) {
    throw InvalidRequestException(
        'cursor must be an opaque value returned by a previous list call',
        'cursor');
  }
}

void validateQueryValue(String key, String value) {
  if (!_queryKey.hasMatch(key)) {
    throw InvalidRequestException('Query parameter names must be alphanumeric');
  }
  if (value.length > 500 || hasControl(value, false)) {
    throw InvalidRequestException('$key has an invalid value', key);
  }
}

void validateBodySize(List<int> body) {
  if (body.length > maxBodyBytes) {
    throw InvalidRequestException(
        'Request body exceeds the $maxBodyBytes byte limit');
  }
}

void validateDateString(String? value, String field) {
  if (value != null && !_dateTime.hasMatch(value)) {
    throw InvalidRequestException(
        '$field must be an RFC 3339 timestamp or a YYYY-MM-DD date', field);
  }
}
