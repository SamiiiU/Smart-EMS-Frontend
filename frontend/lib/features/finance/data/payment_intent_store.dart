import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'secure_storage_platform.dart';

/// Frozen request saved before sending. Unknown outcomes are never auto-retried.
class PaymentIntent {
  const PaymentIntent({
    required this.key,
    required this.invoiceId,
    required this.amount,
    required this.source,
    this.reference,
    this.paymentId,
  });
  final String key, invoiceId, amount, source;
  final String? reference, paymentId;
  Map<String, dynamic> get body => {
    'idempotencyKey': key,
    'invoiceId': invoiceId,
    'amount': amount,
    'source': source,
    if (reference != null) 'reference': reference,
  };
  String encode() =>
      jsonEncode({'version': 1, ...body, 'paymentId': paymentId});
  factory PaymentIntent.decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    if (data['version'] != 1) throw StateError('Unsupported payment intent');
    return PaymentIntent(
      key: data['idempotencyKey'] as String,
      invoiceId: data['invoiceId'] as String,
      amount: data['amount'] as String,
      source: data['source'] as String,
      reference: data['reference'] as String?,
      paymentId: data['paymentId'] as String?,
    );
  }
  PaymentIntent recorded(String id) => PaymentIntent(
    key: key,
    invoiceId: invoiceId,
    amount: amount,
    source: source,
    reference: reference,
    paymentId: id,
  );
}

abstract interface class PaymentIntentStore {
  Future<PaymentIntent?> read(String owner, String invoice);
  Future<void> write(String owner, PaymentIntent intent);
  Future<void> remove(String owner, String invoice);
}

class SecurePaymentIntentStore implements PaymentIntentStore {
  SecurePaymentIntentStore({FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );
  final FlutterSecureStorage storage;
  String _key(String owner, String invoice) =>
      'finance.intent.v1:$owner:$invoice';
  @override
  Future<PaymentIntent?> read(String owner, String invoice) async {
    ensureSecureStorageWebPlatform(); // P0 WEB-INTENT-1 (no-op off web)
    final value = await storage.read(key: _key(owner, invoice));
    if (value == null) return null;
    final intent = PaymentIntent.decode(value);
    if (intent.invoiceId != invoice) {
      throw StateError('Payment intent scope mismatch');
    }
    return intent;
  }

  @override
  Future<void> write(String owner, PaymentIntent intent) {
    ensureSecureStorageWebPlatform();
    return storage.write(key: _key(owner, intent.invoiceId), value: intent.encode());
  }
  @override
  Future<void> remove(String owner, String invoice) {
    ensureSecureStorageWebPlatform();
    return storage.delete(key: _key(owner, invoice));
  }
}

/// Explicit test seam; the application injects secure persistent storage.
class MemoryPaymentIntentStore implements PaymentIntentStore {
  final Map<String, String> _values = {};
  @override
  Future<PaymentIntent?> read(String owner, String invoice) async {
    final value = _values['$owner:$invoice'];
    return value == null ? null : PaymentIntent.decode(value);
  }

  @override
  Future<void> write(String owner, PaymentIntent intent) async {
    _values['$owner:${intent.invoiceId}'] = intent.encode();
  }

  @override
  Future<void> remove(String owner, String invoice) async {
    _values.remove('$owner:$invoice');
  }
}
