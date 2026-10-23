import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/setup/data/setup_repository.dart';
import 'package:smartems/features/setup/domain/setup_models.dart';
import 'package:smartems/features/setup/presentation/academic_year_lifecycle_row.dart';

/// A4: C8 academic-year lifecycle and C10 typed, dated, endable assignments,
/// against a fake adapter answering like the real routes.
class _Server implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int? failStatus;
  String failMessage = 'An academic year can move from active only to closing';

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    if (failStatus != null) {
      final st = failStatus!;
      failStatus = null;
      return _raw(st, jsonEncode({'message': failMessage}));
    }
    final path = o.uri.path;
    if (path.endsWith('/status') || path.endsWith('/classification')) {
      return _raw(
        200,
        jsonEncode({'id': 'y', 'status': (o.data as Map)['status']}),
      );
    }
    if (path == '/api/teaching-assignments') {
      final d = o.data as Map;
      return _raw(
        201,
        jsonEncode({
          'id': 'ta-1',
          'staffId': d['staffId'],
          'sectionId': d['sectionId'],
          'subjectId': d['subjectId'],
          'academicYearId': d['academicYearId'],
          'assignmentType': d['assignmentType'],
          'status': 'active',
          'startsOn': d['startsOn'],
          'endsOn': d['endsOn'],
        }),
      );
    }
    if (path.endsWith('/end')) {
      return _raw(
        200,
        jsonEncode({
          'id': 'ta-1',
          'assignmentType': 'primary',
          'status': 'ended',
          'endsOn': '2026-10-16',
        }),
      );
    }
    return _raw(404, '{"message":"not found"}');
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _raw(int status, String json) => ResponseBody.fromBytes(
  utf8.encode(json),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

({_Server server, SetupRepository repo}) _wire() {
  final server = _Server();
  return (
    server: server,
    repo: SetupRepository(
      Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    ),
  );
}

AcademicYear _year(
  String? status, {
  bool review = false,
  bool current = false,
}) => AcademicYear.fromJson({
  'id': 'y-1',
  'name': '2025-26',
  'startDate': '2025-08-01',
  'endDate': '2026-05-31',
  'current': current,
  'status': status,
  'lifecycleReviewRequired': review,
});

Future<int> _pumpRow(
  WidgetTester tester,
  ({_Server server, SetupRepository repo}) w,
  AcademicYear y,
) async {
  var changed = 0;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(
        body: AcademicYearLifecycleRow(
          year: y,
          repository: w.repo,
          onChanged: () => changed++,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return changed;
}

void main() {
  group('models', () {
    test('year states parse; a legacy year is never treated as archived', () {
      expect(_year('active').status, YearStatus.active);
      final legacy = _year(null, review: true);
      expect(legacy.status, isNull);
      expect(legacy.reviewRequired, isTrue);
      expect(YearStatus.draft.next, YearStatus.active);
      expect(YearStatus.active.next, YearStatus.closing);
      expect(YearStatus.closing.next, YearStatus.archived);
      expect(YearStatus.archived.next, isNull);
    });

    test('assignments carry type, dates and liveness', () {
      final a = TeachingAssignment.fromJson({
        'id': 'a',
        'assignmentType': 'substitute',
        'status': 'scheduled',
        'startsOn': '2026-11-01',
        'endsOn': '2026-11-07',
      });
      expect(a.type, AssignmentType.substitute);
      expect(a.isLive, isTrue);
      expect(a.periodLabel, '2026-11-01 → 2026-11-07');
      expect(
        TeachingAssignment.fromJson({'id': 'b', 'status': 'ended'}).isLive,
        isFalse,
      );
      expect(
        TeachingAssignment.fromJson({'id': 'c'}).type,
        AssignmentType.primary,
        reason: 'legacy rows are open-ended primaries',
      );
    });
  });

  group('requests', () {
    test(
      'typed, dated assignment creation and immediate ending use the real routes',
      () async {
        final w = _wire();
        final created = await w.repo.createAssignment(
          staffId: 's',
          sectionId: 'sec',
          subjectId: 'sub',
          academicYearId: 'y',
          type: AssignmentType.coTeacher,
          startsOn: '2026-11-01',
        );
        expect(w.server.requests.single.data, {
          'staffId': 's',
          'sectionId': 'sec',
          'subjectId': 'sub',
          'academicYearId': 'y',
          'assignmentType': 'co_teacher',
          'startsOn': '2026-11-01',
        });
        expect(created.type, AssignmentType.coTeacher);
        final ended = await w.repo.endAssignment('ta-1');
        expect(
          w.server.requests.last.path,
          '/api/teaching-assignments/ta-1/end',
        );
        expect(ended.isLive, isFalse);
      },
    );

    test('year transition and classification post the target state', () async {
      final w = _wire();
      await w.repo.transitionYear('y-1', YearStatus.closing);
      await w.repo.classifyYear(
        'y-1',
        YearStatus.archived,
        'Session ended May 2025',
      );
      expect(w.server.requests.map((r) => r.path), [
        '/api/academic-years/y-1/status',
        '/api/academic-years/y-1/classification',
      ]);
      expect(w.server.requests.first.data, {'status': 'closing'});
      expect(w.server.requests.last.data, {
        'status': 'archived',
        'reason': 'Session ended May 2025',
      });
    });
  });

  group('year row', () {
    testWidgets('shows the state and offers only the next forward step', (
      tester,
    ) async {
      final w = _wire();
      await _pumpRow(tester, w, _year('active', current: true));
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Start closing'), findsOneWidget);
      expect(find.text('Archive year'), findsNothing);
      await tester.tap(find.text('Start closing'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start closing').last);
      await tester.pumpAndSettle();
      expect(w.server.requests.single.data, {'status': 'closing'});
    });

    testWidgets('an archived year offers no action', (tester) async {
      final w = _wire();
      await _pumpRow(tester, w, _year('archived'));
      expect(find.text('Archived'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      expect(find.textContaining('Archive'), findsOneWidget);
    });

    testWidgets(
      'a legacy year says "Needs classification" and requires a state and a reason',
      (tester) async {
        final w = _wire();
        await _pumpRow(tester, w, _year(null, review: true));
        expect(find.text('Needs classification'), findsOneWidget);
        expect(find.text('Archived'), findsNothing);
        await tester.tap(find.text('Classify year'));
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(TextButton, 'Classify');
        expect(tester.widget<TextButton>(confirm).onPressed, isNull);
        await tester.tap(find.byKey(const Key('classify-status')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archived').last);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextButton>(confirm).onPressed,
          isNull,
          reason: 'reason still missing',
        );
        await tester.enterText(
          find.byType(TextField),
          'Results published in 2025',
        );
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(
          w.server.requests.single.path,
          '/api/academic-years/y-1/classification',
        );
        expect(w.server.requests.single.data, {
          'status': 'archived',
          'reason': 'Results published in 2025',
        });
      },
    );

    testWidgets(
      'a server refusal is shown and nothing is reported as changed',
      (tester) async {
        final w = _wire();
        w.server.failStatus = 409;
        w.server.failMessage =
            'Make another year current before archiving this one';
        var changed = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(role: AppRole.admin),
            home: Scaffold(
              body: AcademicYearLifecycleRow(
                year: _year('closing', current: true),
                repository: w.repo,
                onChanged: () => changed++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive year'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Archive year').last);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Make another year current'),
          findsOneWidget,
        );
        expect(changed, 0);
      },
    );

    testWidgets('cancelling a step sends nothing', (tester) async {
      final w = _wire();
      await _pumpRow(tester, w, _year('draft'));
      await tester.tap(find.text('Activate year'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(w.server.requests, isEmpty);
    });
  });
}
