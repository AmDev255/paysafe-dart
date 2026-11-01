# Examples

`examples.dart` holds the runnable examples; each reads `PAYSAFE_SECRET_KEY`:

```bash
PAYSAFE_SECRET_KEY=paysafe_test_... dart run examples/examples.dart auth
dart run examples/examples.dart create-payment +255712340000
dart run examples/examples.dart verify-webhook      # self-test against the shared vector
```

Names: `auth`, `create-payment`, `get-payment`, `list-payments`, `refund`, `payment-link`, `control-number`, `transfer`, `webhook-endpoints`, `events`, `customers-and-balance`, `verify-webhook`.

`webhooks/shelf_server.dart` shows the same verification inside a Shelf server. `example/example.dart` is the short pub.dev example.
