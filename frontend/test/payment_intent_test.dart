import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/data/payment_intent_store.dart';
import 'package:smartems/features/finance/domain/finance_models.dart';
import 'package:smartems/features/finance/domain/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryPaymentIntentStore store;
  late Dio dio;
  late List<Map<String, dynamic>> sent;
  late bool timeout;
  late int sequence;
  late String owner;
  FinanceRepository repository() => FinanceRepository(
    dio,
    intents: store,
    owner: () => owner,
    newIdempotencyKey: () =>
        '00000000-0000-4000-8000-${(++sequence).toString().padLeft(12, '0')}',
  );
  Future<({String? paymentId, String? error})> pay(
    FinanceRepository repo, {
    String amount = '25.50',
  }) => repo.recordPayment(
    invoiceId: 'invoice',
    amount: Money.parse(amount),
    source: PaymentSource.cash,
  );
  setUp(() {
    store = MemoryPaymentIntentStore();
    sent = [];
    timeout = true;
    sequence = 0;
    owner = 'tenant:user';
    dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          sent.add(Map<String, dynamic>.from(request.data as Map));
          if (timeout) {
            handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.receiveTimeout,
              ),
            );
            return;
          }
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 201,
              data: jsonEncode({'id': 'payment'}),
            ),
          );
        },
      ),
    );
  });
  test(
    'timeout survives repository restart and retries the exact original intent',
    () async {
      final first = await pay(repository());
      expect(first.paymentId, isNull);
      timeout = false;
      final second = await pay(repository());
      expect(second.paymentId, 'payment');
      expect(sent.length, 2);
      expect(sent[0], sent[1]);
      expect(sequence, 1);
      expect((await store.read(owner, 'invoice'))?.paymentId, 'payment');
    },
  );
  test('unknown request cannot be silently changed to a new amount', () async {
    await pay(repository());
    timeout = false;
    final changed = await pay(repository(), amount: '50');
    expect(changed.paymentId, isNull);
    expect(changed.error, contains('original details'));
    expect(sent.length, 1);
  });
  test(
    'concurrent same-isolate submits create only one confirmed payment request',
    () async {
      timeout = false;
      final repo = repository();
      final results = await Future.wait([pay(repo), pay(repo)]);
      expect(results.every((r) => r.paymentId == 'payment'), isTrue);
      expect(sent.length, 1);
    },
  );
  test('account switch cannot inherit another account intent', () async {
    await pay(repository());
    owner = 'tenant:other';
    timeout = false;
    await pay(repository());
    expect(sent[0]['idempotencyKey'], isNot(sent[1]['idempotencyKey']));
    expect((await store.read('tenant:user', 'invoice'))?.paymentId, isNull);
  });
  test('only matching confirmed payment can clear tracking', () async {
    timeout = false;
    final repo = repository();
    await pay(repo);
    await repo.finishPaymentIntent('invoice', 'different');
    expect(await store.read(owner, 'invoice'), isNotNull);
    await repo.finishPaymentIntent('invoice', 'payment');
    expect(await store.read(owner, 'invoice'), isNull);
  });
  test('unreadable recovery storage sends nothing', () async {
    final repo = FinanceRepository(
      dio,
      intents: _BrokenStore(),
      owner: () => owner,
    );
    final result = await pay(repo);
    expect(result.error, contains('storage'));
    expect(sent, isEmpty);
  });
  test('secure store restores scoped intent through a new instance', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final first = SecurePaymentIntentStore();
    const intent = PaymentIntent(
      key: 'key',
      invoiceId: 'invoice',
      amount: '25.50',
      source: 'MANUAL_CASH',
    );
    await first.write('tenant:user', intent);
    final second = SecurePaymentIntentStore();
    expect(
      (await second.read('tenant:user', 'invoice'))?.encode(),
      intent.encode(),
    );
    expect(await second.read('tenant:other', 'invoice'), isNull);
  });
}

class _BrokenStore implements PaymentIntentStore {
  @override
  Future<PaymentIntent?> read(String owner, String invoice) async =>
      throw StateError('fixture');
  @override
  Future<void> write(String owner, PaymentIntent intent) async =>
      throw StateError('fixture');
  @override
  Future<void> remove(String owner, String invoice) async =>
      throw StateError('fixture');
}
