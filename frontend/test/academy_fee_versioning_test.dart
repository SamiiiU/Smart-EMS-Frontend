import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/academy/data/academy_repository.dart';
import 'package:smartems/features/academy/domain/academy_models.dart';
import 'package:smartems/features/academy/presentation/batch_fee_panel.dart';

/// V50 fee versioning UI: current vs scheduled vs past prices, scheduling a future price,
/// explicit adjustments for existing learners, and server refusals shown in plain words.
class _Server implements HttpClientAdapter {
  _Server(this.routes);
  final Map<String, Object Function(RequestOptions o)> routes;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    final h = routes['${o.method} ${o.path}'];
    final r = h == null ? (404, {'message': 'Not found'}) : h(o);
    final (status, body) = r is (int, Object) ? r : (200, r);
    return ResponseBody.fromBytes(
      utf8.encode(body is String ? body : jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const _batch = Batch(
  id: 'b1',
  name: 'A',
  status: 'open',
  campusId: 'c1',
  offeringId: 'o',
  offeringName: 'O',
  courseName: 'Physics',
  courseCode: 'PHY',
  startDate: '2026-01-01',
  endDate: '2027-12-31',
  activeLearners: 2,
);

String _fee({bool scheduled = true}) =>
    '{"id":"v1","fee_head_name":"Tuition","amount":3000.00,"frequency":"monthly","due_day":10,'
    '"current_month":"2026-10","adjustments":0,"versions":['
    '{"id":"v0","amount":2800.00,"effective_from":"2026-01","reason":"Launch","due_day":10},'
    '{"id":"v1","amount":3000.00,"effective_from":"2026-06","reason":"Mid-year","due_day":10}'
    '${scheduled ? ',{"id":"v2","amount":3500.00,"effective_from":"2026-12","reason":"Annual revision","due_day":10}' : ''}]}';

Future<_Server> _pump(
  WidgetTester tester,
  Map<String, Object Function(RequestOptions)> extra, {
  bool scheduled = true,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = _Server({
    'GET /api/academy/batches/b1/fee': (_) => _fee(scheduled: scheduled),
    'GET /api/academy/finance/batches/b1/invoices': (_) => {
      'invoices': [],
      'totals': {},
    },
    ...extra,
  });
  final repo = AcademyRepository(
    Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = s,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(
        body: BatchFeePanel(repository: repo, batch: _batch),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

void main() {
  test(
    'model: amounts stay exact and scheduled versions are those after the current month',
    () {
      final fee = BatchFee.fromJson(AcademyRepository.decode(_fee()) as Map);
      expect(fee.amount, '3000.00');
      expect(fee.versions.map((v) => v.amount), [
        '2800.00',
        '3000.00',
        '3500.00',
      ]);
      expect(fee.scheduled.single.effectiveFrom, '2026-12');
    },
  );

  testWidgets(
    'history distinguishes current, scheduled and past prices; issued invoices are said to be unchanged',
    (tester) async {
      await _pump(tester, {});
      expect(find.text('PKR 3,500.00 from 2026-12'), findsOneWidget);
      expect(find.text('PKR 2,800.00 from 2026-01'), findsOneWidget);
      expect(find.text('scheduled'), findsOneWidget);
      expect(find.text('current'), findsOneWidget);
      expect(find.text('past'), findsOneWidget);
      expect(
        find.textContaining('Issued invoices never change'),
        findsOneWidget,
      );
      expect(find.text('Apply to existing learners'), findsOneWidget);
    },
  );

  testWidgets(
    'scheduling sends amount, month and reason; backdated refusal is explained',
    (tester) async {
      var calls = 0;
      final s = await _pump(tester, {
        'POST /api/academy/batches/b1/fee/versions': (o) => ++calls == 1
            ? (
                409,
                {
                  'status': 409,
                  'message':
                      'RETROACTIVE_PRICE: invoices already exist for 2026-11',
                },
              )
            : _fee(),
      });
      await tester.tap(find.text('Schedule price change'));
      await tester.pumpAndSettle();
      expect(find.textContaining('unless you apply an adjustment'), findsOneWidget);
      final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), '3600.00');
      await tester.enterText(fields.at(1), '2026-11');
      await tester.enterText(fields.at(2), 'Annual revision');
      await tester.pump();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('past or already-invoiced month'),
        findsOneWidget,
        reason: 'dialog stays open with the reason',
      );
      await tester.enterText(fields.at(1), '2027-01');
      await tester.pump();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      final post = s.requests.lastWhere((r) => r.method == 'POST').data as Map;
      expect(post, {
        'amount': '3600.00',
        'effectiveFrom': '2027-01',
        'reason': 'Annual revision',
      });
    },
  );

  testWidgets(
    'adjusting existing learners is explicit, warns, and sends version, month and reason',
    (tester) async {
      final s = await _pump(tester, {
        'POST /api/academy/batches/b1/fee/adjustments': (_) => {'adjusted': 2},
      });
      await tester.tap(find.text('Apply to existing learners'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'changes the agreed price of every current learner',
        ),
        findsOneWidget,
      );
      expect(find.text('Applies from 2026-12'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).last,
        'Agreed with parents',
      );
      await tester.pump();
      await tester.tap(find.text('Apply adjustment'));
      await tester.pumpAndSettle();
      final post = s.requests.lastWhere((r) => r.method == 'POST').data as Map;
      expect(post['versionId'], 'v2');
      expect(post['appliesFrom'], '2026-12');
      expect(post['reason'], 'Agreed with parents');
      expect(
        post.containsKey('enrollmentIds'),
        isFalse,
        reason: 'all current learners',
      );
    },
  );

  testWidgets('no scheduled price: no adjustment action is offered', (
    tester,
  ) async {
    await _pump(tester, {}, scheduled: false);
    expect(find.text('Apply to existing learners'), findsNothing);
    expect(find.text('Schedule price change'), findsOneWidget);
  });
}
