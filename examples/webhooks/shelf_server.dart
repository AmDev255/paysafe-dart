// Shelf handler for PaySafe webhooks: `PAYSAFE_WEBHOOK_SECRET=... dart run examples/webhooks/shelf_server.dart`.
import 'dart:io';

import 'package:paysafe_tz/paysafe_tz.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final secret = Platform.environment['PAYSAFE_WEBHOOK_SECRET']!;
  final seen = <String>{};

  Future<Response> handler(Request request) async {
    if (request.method != 'POST' || request.url.path != 'paysafe/webhook') {
      return Response.notFound('not found');
    }
    final rawBody = await request
        .read()
        .fold<List<int>>([], (a, b) => a..addAll(b)); // exact bytes
    final Event event;
    try {
      event = Webhooks.constructEvent(secret, rawBody,
          request.headers[Webhooks.signatureHeader.toLowerCase()]);
    } on SignatureVerificationException catch (e) {
      return Response(400, body: 'invalid signature: ${e.reason}');
    }
    if (!seen.add(event.id)) return Response.ok('duplicate');
    switch (event.type) {
      case 'payment.succeeded':
        print(
            'paid ${event.payment?.id} ${event.payment?.amount}'); // mark the order paid
      case 'payment.failed' || 'payment.expired':
        print('not paid: ${event.type}');
      default:
        print('ignored ${event.type}');
    }
    return Response.ok('ok');
  }

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
  print(
      'Listening on http://${server.address.host}:${server.port}/paysafe/webhook');
}
