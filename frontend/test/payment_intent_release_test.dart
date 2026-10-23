import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/data/payment_intent_store.dart';
import 'package:smartems/features/finance/data/secure_storage_platform.dart';
import 'package:smartems/features/finance/domain/finance_models.dart';
import 'package:smartems/features/finance/domain/money.dart';

/// P0 WEB-INTENT-1 regression set (VM side). The web-only part of the fix is
/// verified against the real optimised web output in
/// deploy/local-staging/e2e/finance-release-check.cjs.

class _WriteFails implements PaymentIntentStore {
  @override
  Future<PaymentIntent?> read(String owner, String invoice) async => null;
  @override
  Future<void> write(String owner, PaymentIntent intent) async =>
      throw StateError('storage full');
  @override
  Future<void> remove(String owner, String invoice) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Object?> sent;
  late Dio dio;

  setUp(() {
    sent = [];
    dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            sent.add(r.data);
            h.reject(
              DioException(
                requestOptions: r,
                type: DioExceptionType.receiveTimeout,
              ),
            );
          },
        ),
      );
  });

  Future<({String? paymentId, String? error})> pay(PaymentIntentStore store) =>
      FinanceRepository(
        dio,
        intents: store,
        owner: () => 'tenant:user',
      ).recordPayment(
        invoiceId: 'invoice',
        amount: Money.parse('25.50'),
        source: PaymentSource.cash,
      );

  test('a failed storage WRITE prevents submission (nothing sent)', () async {
    final r = await pay(_WriteFails());
    expect(r.error, contains('storage'));
    expect(sent, isEmpty);
  });

  test(
    'a corrupted stored record blocks submission and is not overwritten',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'finance.intent.v1:tenant:user:invoice': '{not json',
      });
      final store = SecurePaymentIntentStore();
      final r = await pay(store);
      expect(r.error, contains('storage'));
      expect(sent, isEmpty);
      // Still the corrupted value: recovery is never silently replaced.
      expect(
        await const FlutterSecureStorage().read(
          key: 'finance.intent.v1:tenant:user:invoice',
        ),
        '{not json',
      );
    },
  );

  test(
    'records written in the existing v1 format stay readable after the fix',
    () async {
      const existing = PaymentIntent(
        key: 'k-1',
        invoiceId: 'invoice',
        amount: '25.50',
        source: 'MANUAL_CASH',
      );
      FlutterSecureStorage.setMockInitialValues({
        'finance.intent.v1:tenant:user:invoice': existing.encode(),
      });
      final read = await SecurePaymentIntentStore().read(
        'tenant:user',
        'invoice',
      );
      expect(read?.encode(), existing.encode());
      expect(
        await SecurePaymentIntentStore().read('tenant:other', 'invoice'),
        isNull,
        reason: 'account isolation',
      );
    },
  );

  test(
    'pending record survives a "reload" and the retry reuses its key',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final first = await pay(
        SecurePaymentIntentStore(),
      ); // timeout -> uncertain
      expect(first.paymentId, isNull);
      // New store instance = app reload.
      final second = await pay(SecurePaymentIntentStore());
      expect(second.paymentId, isNull);
      expect(sent, hasLength(2));
      expect(
        (sent[0] as Map)['idempotencyKey'],
        (sent[1] as Map)['idempotencyKey'],
      );
    },
  );

  test(
    'the web guard is a no-op off web (the mobile/test platform stays in place)',
    () async {
      FlutterSecureStorage.setMockInitialValues({'x': 'y'});
      ensureSecureStorageWebPlatform();
      expect(await const FlutterSecureStorage().read(key: 'x'), 'y');
    },
  );
}
