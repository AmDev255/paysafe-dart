// Minimal pub.dev example. The full set lives in examples/ (see examples/README.md).
import 'package:paysafe_tz/paysafe_tz.dart';

Future<void> main() async {
  final client = PaySafeClient(); // reads PAYSAFE_SECRET_KEY
  final payment = await client.payments.create(
    const CreatePaymentParams(
        amount: 10000,
        customer: CustomerParams(phone: '+255712340000'),
        reference: 'order-8812'),
    RequestOptions.withIdempotencyKey('order-8812-attempt-1'),
  );
  final done = await client.payments.waitForTerminal(payment.id);
  print('${done.id} ${done.status}');
  client.close();
}
