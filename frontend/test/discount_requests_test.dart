import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/data/payment_intent_store.dart';
import 'package:smartems/features/finance/presentation/discount_requests_screen.dart';
import 'package:smartems/features/finance/domain/money.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Dio dio;
  late MemoryPaymentIntentStore store;
  late List<RequestOptions> sent;
  late bool timeout, denied, canDecide;
  late String owner;
  late int sequence;
  FinanceRepository repository() => FinanceRepository(
    dio,
    intents: store,
    owner: () => owner,
    newIdempotencyKey: () =>
        '00000000-0000-4000-8000-${(++sequence).toString().padLeft(12, '0')}',
  );
  Future<String> submit(FinanceRepository repo, {String value = '100.00'}) =>
      repo.requestDiscount(
        invoiceId: 'invoice',
        value: value,
        percentage: false,
        description: 'Scholarship review',
      );
  setUp(() {
    store = MemoryPaymentIntentStore();
    sent = [];
    timeout = false;
    denied = false;
    canDecide = false;
    owner = 'tenant:user';
    sequence = 0;
    dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          sent.add(request);
          if (denied) {
            handler.reject(
              DioException(
                requestOptions: request,
                response: Response(
                  requestOptions: request,
                  statusCode: 403,
                  data: '{"message":"Access denied"}',
                ),
                type: DioExceptionType.badResponse,
              ),
            );
            return;
          }
          if (timeout && request.method == 'POST') {
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
              statusCode: 200,
              data: request.method == 'GET'
                  ? '[{"id":"request","requested_amount":100.00,"requested_percentage":null,"status":"pending_approval","description":"Scholarship review","canDecide":$canDecide}]'
                  : jsonEncode({'id': 'request', 'status': 'pending_approval'}),
            ),
          );
        },
      ),
    );
  });
  test(
    'discount timeout survives repository restart with original operation and exact amount',
    () async {
      timeout = true;
      await expectLater(submit(repository()), throwsA(isA<Object>()));
      timeout = false;
      expect(await submit(repository()), 'request');
      expect(sequence, 1);
      expect(sent.length, 2);
      expect(
        sent[0].headers['Idempotency-Key'],
        sent[1].headers['Idempotency-Key'],
      );
      expect(sent[1].data['amount'], '100.00');
      expect(
        (await store.read(owner, 'discount:invoice'))?.paymentId,
        'request',
      );
    },
  );
  test(
    'uncertain discount cannot change amount or create a second operation',
    () async {
      timeout = true;
      await expectLater(submit(repository()), throwsA(isA<Object>()));
      await expectLater(
        submit(repository(), value: '200.00'),
        throwsStateError,
      );
      expect(sent.length, 1);
      expect(sequence, 1);
    },
  );
  test(
    'discount intent is separate from payment intent and another account',
    () async {
      timeout = true;
      await expectLater(submit(repository()), throwsA(isA<Object>()));
      expect(await store.read(owner, 'invoice'), isNull);
      owner = 'tenant:other';
      timeout = false;
      await submit(repository());
      expect(sequence, 2);
      expect(
        sent[0].headers['Idempotency-Key'],
        isNot(sent[1].headers['Idempotency-Key']),
      );
    },
  );
  test(
    'explicit denial clears a new rejected intent and keeps decimal decoding exact',
    () async {
      denied = true;
      await expectLater(submit(repository()), throwsA(isA<Object>()));
      expect(await store.read(owner, 'discount:invoice'), isNull);
      denied = false;
      final rows = await repository().loadDiscountRequests('invoice');
      expect(rows.single['requested_amount'], '100.00');
    },
  );
  Widget host() => MaterialApp(
    theme: AppTheme.light(role: AppRole.admin),
    home: DiscountRequestsScreen(
      repository: repository(),
      invoiceId: 'invoice',
    ),
  );
  testWidgets('maker sees pending state without approval actions', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    // Track B: formatted money + human status, never the raw server code.
    expect(find.text(Money.parse('100.00').format()), findsOneWidget);
    expect(find.text('Status: Awaiting approval'), findsOneWidget);
    expect(find.textContaining('pending_approval'), findsNothing);
    expect(find.text('Approve discount'), findsNothing);
    expect(find.text('Request discount'), findsOneWidget);
  });
  testWidgets('reject requires a reason; cancel and blank reason send nothing', (
    tester,
  ) async {
    canDecide = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final before = sent.length;
    await tester.ensureVisible(find.text('Reject discount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject discount'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discount-decision-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a reason to reject.'), findsOneWidget);
    expect(sent.length, before, reason: 'blank reason must not send a decision');
    await tester.tap(find.byKey(const Key('discount-decision-cancel')));
    await tester.pumpAndSettle();
    expect(sent.length, before, reason: 'cancel must not send a decision');
    await tester.ensureVisible(find.text('Reject discount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject discount'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byKey(const Key('discount-reject-reason')), matching: find.byType(EditableText)), 'Not eligible');
    await tester.tap(find.byKey(const Key('discount-decision-confirm')));
    await tester.pumpAndSettle();
    final decision = sent.where((r) => r.method == 'POST' && r.path.contains('/reject')).toList();
    expect(decision, hasLength(1));
    expect(jsonEncode(decision.single.data), contains('Not eligible'));
  });
  testWidgets('approve dialog states MFA and self-approval rules', (tester) async {
    canDecide = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Approve discount'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve discount'));
    await tester.pumpAndSettle();
    expect(find.textContaining('fresh MFA verification is required'), findsOneWidget);
    expect(find.textContaining('cannot approve your own request'), findsOneWidget);
  });
  testWidgets('meets tap-target and labelled-control guidelines', (tester) async {
    canDecide = true;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
  testWidgets('server-authorized checker sees decision controls', (
    tester,
  ) async {
    canDecide = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Approve discount'), findsOneWidget);
    expect(find.text('Reject discount'), findsOneWidget);
  });
  testWidgets('denied load exposes no protected rows or request form', (
    tester,
  ) async {
    denied = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('Request discount'), findsNothing);
    expect(find.text('Scholarship review'), findsNothing);
  });
}
