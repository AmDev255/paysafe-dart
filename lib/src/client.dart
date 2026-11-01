import 'dart:async';
import 'dart:convert';
import 'dart:io' show IOException, Platform;
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_response.dart';
import 'errors.dart';
import 'models.dart';
import 'params.dart';
import 'request_options.dart';
import 'validate.dart';

part 'page.dart';
part 'resources.dart';

/// Sandbox or production, derived from the key prefix.
enum PaySafeEnvironment { test, live }

/// Client for one PaySafe project in one environment. Create one per process and reuse it.
class PaySafeClient {
  /// [apiKey] defaults to PAYSAFE_SECRET_KEY, [baseUrl] to PAYSAFE_BASE_URL. [timeout] is per attempt;
  /// [maxRetries] counts retries after the first attempt. [logger] receives one record per attempt (never the
  /// key or bodies). Pass your own [httpClient] to reuse connections; redirects are disabled per request.
  /// [sleeper] and [random] are test hooks.
  PaySafeClient({
    String? apiKey,
    String? baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 4,
    this.apiVersion,
    http.Client? httpClient,
    this.logger,
    String? userAgentSuffix,
    bool allowInsecureHttp = false,
    Future<void> Function(Duration)? sleeper,
    double Function()? random,
  })  : _sleeper = sleeper ?? ((d) => Future<void>.delayed(d)),
        _random = random ?? Random.secure().nextDouble {
    final key = apiKey ?? Platform.environment['PAYSAFE_SECRET_KEY'];
    if (key == null || key.isEmpty) {
      throw ConfigurationException(
          'No API key given and PAYSAFE_SECRET_KEY is not set');
    }
    if (!apiKeyPattern.hasMatch(key)) {
      throw ConfigurationException('API key contains invalid characters');
    }
    if (key.startsWith('paysafe_test_')) {
      environment = PaySafeEnvironment.test;
    } else if (key.startsWith('paysafe_live_')) {
      environment = PaySafeEnvironment.live;
    } else {
      throw ConfigurationException(
          'API key must start with paysafe_test_ or paysafe_live_');
    }
    _apiKey = key;
    var url = baseUrl ?? Platform.environment['PAYSAFE_BASE_URL'];
    if (url == null || url.isEmpty) url = defaultBaseUrl;
    if (url.contains(RegExp(r'\s')) || hasControl(url, false)) {
      throw ConfigurationException(
          'baseUrl contains whitespace or control characters');
    }
    url = url.replaceAll(RegExp(r'/+$'), '');
    if (url.endsWith('/v1')) url = url.substring(0, url.length - 3);
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw ConfigurationException(
          'baseUrl must be an absolute URL without credentials, query or fragment');
    }
    if (parsed.scheme != 'https' &&
        !(parsed.scheme == 'http' &&
            (allowInsecureHttp || isLoopback(parsed.host)))) {
      throw ConfigurationException(
          'baseUrl must use https (plain http is only allowed for localhost or with allowInsecureHttp)');
    }
    _baseUrl = url;
    if (timeout <= Duration.zero) {
      throw ConfigurationException('timeout must be positive');
    }
    if (maxRetries < 0) {
      throw ConfigurationException('maxRetries must be zero or more');
    }
    if (userAgentSuffix != null && hasControl(userAgentSuffix, false)) {
      throw ConfigurationException(
          'userAgentSuffix contains control characters');
    }
    _userAgent =
        'paysafe-dart/$version (Dart ${Platform.version.split(' ').first}; ${Platform.operatingSystem})'
        '${userAgentSuffix != null ? ' $userAgentSuffix' : ''}';
    _http = httpClient ?? http.Client();
    _ownsHttp = httpClient == null;
    payments = PaymentsResource._(this);
    paymentLinks = PaymentLinksResource._(this);
    controlNumbers = ControlNumbersResource._(this);
    refunds = RefundsResource._(this);
    balance = BalanceResource._(this);
    customers = CustomersResource._(this);
    transfers = TransfersResource._(this);
    webhookEndpoints = WebhookEndpointsResource._(this);
    events = EventsResource._(this);
  }

  static const version = '0.1.0';
  static const defaultBaseUrl = 'https://api.paysafe.co.tz';
  static const maxResponseBytes = 16 * 1024 * 1024;
  static const _initialBackoffMs = 500;
  static const _maxBackoffMs = 8000;
  static const _inProgressSleep = Duration(seconds: 1);

  final Duration timeout;
  final int maxRetries;
  final String? apiVersion;
  final void Function(LogRecord)? logger;
  final Future<void> Function(Duration) _sleeper;
  final double Function() _random;
  late final PaySafeEnvironment environment;
  late final String _apiKey;
  late final String _baseUrl;
  late final String _userAgent;
  late final http.Client _http;
  late final bool _ownsHttp;

  late final PaymentsResource payments;
  late final PaymentLinksResource paymentLinks;
  late final ControlNumbersResource controlNumbers;
  late final RefundsResource refunds;
  late final BalanceResource balance;
  late final CustomersResource customers;
  late final TransfersResource transfers;
  late final WebhookEndpointsResource webhookEndpoints;
  late final EventsResource events;

  /// Closes the HTTP client when the SDK created it.
  void close() {
    if (_ownsHttp) _http.close();
  }

  @override
  String toString() =>
      'PaySafeClient(environment=$environment, baseUrl=$_baseUrl)';

  /// Low-level escape hatch: any method and path under /v1 with the raw [ApiResponse].
  Future<ApiResponse> request(
    String method,
    String path, {
    Map<String, String?> query = const {},
    List<int>? body,
    RequestOptions? options,
  }) =>
      _send(method.toUpperCase(), '/${path.replaceAll(RegExp(r'^/+'), '')}',
          query, body, options);

  Future<void> _pause(Duration d) => _sleeper(d);

  Future<ApiResponse> _send(
    String method,
    String path,
    Map<String, String?> query,
    List<int>? body,
    RequestOptions? options,
  ) async {
    final opts = RequestOptions.orDefault(options);
    final target = StringBuffer(_baseUrl)..write(path);
    var first = true;
    for (final entry in query.entries) {
      final value = entry.value;
      if (value == null) continue;
      validateQueryValue(entry.key, value);
      target
        ..write(first ? '?' : '&')
        ..write(Uri.encodeComponent(entry.key))
        ..write('=')
        ..write(Uri.encodeComponent(value));
      first = false;
    }
    if (body != null) validateBodySize(body);
    final uri = Uri.parse(target.toString());
    final retryable = method == 'GET' ||
        method == 'DELETE' ||
        method == 'PATCH' ||
        opts.idempotencyKey != null;
    final maxAttempts = 1 + (opts.maxRetries ?? maxRetries);
    var attempt = 0;
    while (true) {
      attempt++;
      final started = Stopwatch()..start();
      ApiResponse response;
      try {
        response = await _sendOnce(method, uri, body, opts);
      } on ApiConnectionException catch (e) {
        _log(method, path, null, attempt, started, null, e.message);
        if (!retryable ||
            attempt >= maxAttempts ||
            e is ResponseTooLargeException) {
          rethrow;
        }
        await _sleeper(_backoff(attempt));
        continue;
      }
      _log(method, path, response.status, attempt, started, response.requestId,
          null);
      if (response.status < 300) return response;
      if (response.status < 400) {
        throw ApiException(
          status: response.status,
          code: 'unexpected_redirect',
          message:
              'The API answered with a redirect, which this SDK never follows',
          requestId: response.requestId,
          headers: response.headers,
        );
      }
      final error = mapApiError(response);
      final delay = _retryDelay(error, retryable, attempt);
      if (delay == null || attempt >= maxAttempts) throw error;
      await _sleeper(delay);
    }
  }

  Duration? _retryDelay(ApiException error, bool retryable, int attempt) {
    if (error.code == 'idempotency_in_progress') return _inProgressSleep;
    if (error.status == 429 || error.status == 503) {
      final after = error.retryAfter;
      return after != null ? Duration(seconds: after) : _backoff(attempt);
    }
    if (error.status >= 500 && error.code != 'provider_error' && retryable) {
      return _backoff(attempt);
    }
    return null;
  }

  Duration _backoff(int attempt) {
    final ceiling =
        min(_maxBackoffMs, _initialBackoffMs << min(attempt - 1, 20));
    return Duration(milliseconds: (_random() * (ceiling + 1)).floor());
  }

  Future<ApiResponse> _sendOnce(
      String method, Uri uri, List<int>? body, RequestOptions opts) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $_apiKey'
      ..headers['Accept'] = 'application/json'
      ..headers['User-Agent'] = _userAgent;
    if (apiVersion != null) request.headers['PaySafe-Version'] = apiVersion!;
    if (opts.idempotencyKey != null) {
      request.headers['Idempotency-Key'] = opts.idempotencyKey!;
    }
    if (opts.requestId != null) {
      request.headers['X-Request-ID'] = opts.requestId!;
    }
    request.headers.addAll(opts.headers);
    if (body != null) {
      request.bodyBytes = body;
      request.headers['Content-Type'] = 'application/json';
    }
    final perAttempt = opts.timeout ?? timeout;
    try {
      final streamed = await _http.send(request).timeout(perAttempt);
      final headers = <String, String>{};
      streamed.headers.forEach((k, v) => headers[k.toLowerCase()] = v);
      if ((streamed.contentLength ?? 0) > maxResponseBytes) {
        throw ResponseTooLargeException();
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in streamed.stream.timeout(perAttempt)) {
        builder.add(chunk);
        if (builder.length > maxResponseBytes) {
          throw ResponseTooLargeException();
        }
      }
      return ApiResponse(streamed.statusCode, headers, builder.takeBytes(),
          opts.idempotencyKey);
    } on TimeoutException {
      throw ApiTimeoutException(
          'Request to PaySafe timed out after ${perAttempt.inMilliseconds} ms');
    } on http.ClientException catch (e) {
      throw ApiConnectionException('Could not reach PaySafe: ${e.message}');
    } on IOException catch (e) {
      throw ApiConnectionException('Could not reach PaySafe: $e');
    }
  }

  void _log(String method, String path, int? status, int attempt,
      Stopwatch started, String? requestId, String? error) {
    logger?.call(LogRecord(
      method: method,
      path: path,
      status: status,
      attempt: attempt,
      duration: started.elapsed,
      requestId: requestId,
      error: error,
    ));
  }
}
