import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:paysafe_tz/paysafe_tz.dart';

const testKey = 'paysafe_test_9f2Kx7Qm3Rt8Vw2Yz5Ab1Cd4Ef6Gh9Jk';
const requestIdValue = 'req_01J7A9Q0K3M4N5P6R7S8T9V0W1';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('tests/fixtures/$name.json').readAsStringSync())
        as Map<String, dynamic>;

/// The first 2xx response of an operation fixture.
(int, Object?, Map<String, String>) successOf(Map<String, dynamic> f) {
  final responses = f['responses'] as Map<String, dynamic>;
  final code = responses.keys.firstWhere((k) => k.startsWith('2'));
  final r = responses[code] as Map<String, dynamic>;
  return (int.parse(code), r['body'], headerMap(r['headers']));
}

Map<String, String> headerMap(Object? node) => node is Map<String, dynamic>
    ? node.map((k, v) => MapEntry(k, v as String))
    : {};

String? str(Map<String, dynamic> m, String key) => m[key] as String?;

int? integer(Map<String, dynamic> m, String key) => m[key] as int?;

class Recorded {
  Recorded(this.method, this.url, this.headers, this.body);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final List<int> body;

  String? header(String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name.toLowerCase()) return e.value;
    }
    return null;
  }

  String get bodyText => utf8.decode(body);
}

class FakeClient extends http.BaseClient {
  final List<Future<http.StreamedResponse> Function()> steps = [];
  final List<Recorded> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    requests.add(
        Recorded(request.method, request.url, Map.of(request.headers), body));
    if (steps.isEmpty) {
      throw StateError('No scripted response for ${request.url}');
    }
    return steps.removeAt(0)();
  }
}

class Harness {
  Harness({
    int maxRetries = 4,
    Duration timeout = const Duration(seconds: 30),
    String? apiVersion,
    void Function(LogRecord)? logger,
  }) {
    client = PaySafeClient(
      apiKey: testKey,
      baseUrl: 'https://api.test.invalid',
      maxRetries: maxRetries,
      timeout: timeout,
      apiVersion: apiVersion,
      httpClient: server,
      logger: logger,
      sleeper: (d) async => sleeps.add(d),
      random: () => 0.5,
    );
  }

  final FakeClient server = FakeClient();
  final List<Duration> sleeps = [];
  late final PaySafeClient client;

  int get requestCount => server.requests.length;

  Duration get totalSleep => sleeps.fold(Duration.zero, (a, b) => a + b);

  Recorded request([int index = 0]) => server.requests[index];

  Harness enqueueJson(int status, Object? body,
      [Map<String, String> headers = const {}]) {
    final bytes = body == null ? <int>[] : utf8.encode(jsonEncode(body));
    return enqueueBytes(
        status, bytes, body == null ? null : 'application/json', headers);
  }

  Harness enqueueRaw(int status, String body,
          [Map<String, String> headers = const {}]) =>
      enqueueBytes(status, utf8.encode(body), null, headers);

  Harness enqueueBytes(int status, List<int> bytes, String? contentType,
      Map<String, String> headers) {
    final all = <String, String>{};
    if (contentType != null) all['Content-Type'] = contentType;
    all['X-Request-ID'] = requestIdValue;
    all.addAll(headers);
    return enqueueResponse(http.StreamedResponse(Stream.value(bytes), status,
        headers: all, contentLength: bytes.length));
  }

  Harness enqueueResponse(http.StreamedResponse response) {
    server.steps.add(() async => response);
    return this;
  }

  Harness enqueueDisconnect() {
    server.steps.add(
        () async => throw http.ClientException('Connection reset by peer'));
    return this;
  }

  Harness enqueueHang() {
    server.steps.add(() => Completer<http.StreamedResponse>().future);
    return this;
  }
}
