import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_error_mapper.dart';
import 'package:smartems/core/router/teacher_destinations.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/diary/data/diary_repository.dart';
import 'package:smartems/features/diary/domain/diary_models.dart';
import 'package:smartems/features/diary/presentation/diary_editor_screen.dart';
import 'package:smartems/features/student/presentation/student_timetable_unavailable.dart';
import 'package:smartems/features/timetable/data/timetable_repository.dart';

const _sec = 'sec-1';
const _sub = 'sub-1';
final _date = DateTime(2026, 9, 18);
final _key = DiaryKey(sectionId: _sec, subjectId: _sub, date: _date);

/// A stub diary server with the backend's VERIFIED semantics:
/// - GET section?date → every entry for that section + date;
/// - POST on an existing (section, subject, date) → 409;
/// - PUT is a FULL REPLACE — any field missing from the body becomes null.
///
/// Encoding the real semantics (rather than returning canned bodies) is what
/// lets the PUT-guard test catch a form that ever submits a partial body.
class _DiaryServer implements HttpClientAdapter {
  final Map<String, Map<String, dynamic>> rows = {};
  final List<RequestOptions> requests = [];
  bool unreachable = false;
  bool failGet = false;
  bool raceOnPost = false;
  int _next = 0;

  void seed(Map<String, dynamic> row) => rows[row['id'] as String] = row;

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    if (unreachable) {
      throw DioException(
          requestOptions: o, type: DioExceptionType.connectionError);
    }
    final path = o.uri.path;
    if (o.method == 'GET' && path.startsWith('/api/diary/section/')) {
      if (failGet) return _json(500, {'message': 'Server exploded'});
      final date = o.uri.queryParameters['date'];
      return _json(
        200,
        rows.values
            .where((r) => r['sectionId'] == _sec && r['diaryDate'] == date)
            .toList(),
      );
    }
    final body = o.data as Map<String, dynamic>;
    if (o.method == 'POST') {
      final clash = rows.values.any((r) =>
          r['sectionId'] == body['sectionId'] &&
          r['subjectId'] == body['subjectId'] &&
          r['diaryDate'] == body['diaryDate']);
      if (clash || raceOnPost) {
        return _json(409, {
          'status': 409,
          'error': 'Conflict',
          'message': 'Conflicts with existing data',
        });
      }
      final row = {..._fullReplace(body), 'id': 'e-${_next++}'};
      rows[row['id'] as String] = row;
      return _json(201, row);
    }
    if (o.method == 'PUT') {
      final id = path.split('/').last;
      final existing = rows[id];
      if (existing == null) return _json(404, {'message': 'not found'});
      final row = {
        ..._fullReplace(body),
        'id': id,
        'authorName': existing['authorName'],
      };
      rows[id] = row;
      return _json(200, row);
    }
    return _json(404, {'message': 'no route'});
  }

  /// Every content field is taken from the body — ABSENT means null.
  static Map<String, dynamic> _fullReplace(Map<String, dynamic> body) => {
        'sectionId': body['sectionId'],
        'subjectId': body['subjectId'],
        'diaryDate': body['diaryDate'],
        'title': body['title'],
        'homework': body['homework'],
        'classwork': body['classwork'],
        'note': body['note'],
        'authorName': 'Ayesha Khan',
      };

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

DiaryRepository _repo(_DiaryServer s) => DiaryRepository(
    Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = s);

Map<String, dynamic> _existingRow({String author = 'Ayesha Khan'}) => {
      'id': 'e-existing',
      'sectionId': _sec,
      'subjectId': _sub,
      'diaryDate': '2026-09-18',
      'title': 'Fractions',
      'homework': 'Page 12',
      'classwork': 'Worked examples',
      'note': 'Bring a ruler',
      'authorName': author,
    };

Widget _host(Widget child, {double textScale = 1, TextDirection? dir}) =>
    MaterialApp(
      theme: AppTheme.light(role: AppRole.teacher),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: dir == null
            ? child
            : Directionality(textDirection: dir, child: child),
      ),
    );

Widget _editor(_DiaryServer s, {String? me = 'Ayesha Khan'}) =>
    DiaryEditorScreen(
      repository: _repo(s),
      diaryKey: _key,
      heading: 'Grade 5-5-A',
      subjectLabel: 'English',
      currentTeacherName: me,
    );

Iterable<String> _methods(_DiaryServer s) =>
    s.requests.map((r) => r.method);

/// A tall viewport, so the whole form is laid out: ListView builds only what
/// is on screen, and finding an off-screen button would fail for layout
/// reasons rather than behaviour.
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.text('Save'), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  group('Edit-first — asserted both ways', () {
    testWidgets('existing entry → opens pre-filled → save is PUT, never POST',
        (tester) async {
      final s = _DiaryServer()..seed(_existingRow());
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();

      expect(find.text('Fractions'), findsOneWidget);
      expect(find.text('Page 12'), findsOneWidget);
      expect(find.textContaining('No diary written'), findsNothing);

      await tester.enterText(find.text('Page 12'), 'Page 13');
      await _tapSave(tester);

      expect(_methods(s), isNot(contains('POST')));
      expect(s.requests.last.method, 'PUT');
      expect(s.requests.last.uri.path, '/api/diary/e-existing');
      expect(find.text('Saved.'), findsOneWidget);
    });

    testWidgets('no entry → opens blank → save is POST', (tester) async {
      final s = _DiaryServer();
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();

      // "No entry yet" is a NORMAL state: an info line, not an error.
      expect(find.textContaining('No diary written'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      await tester.enterText(find.byType(TextField).at(2), 'Page 5');
      await _tapSave(tester);

      expect(s.requests.last.method, 'POST');
      expect(_methods(s), isNot(contains('PUT')));
    });

    testWidgets('a second save after a create is an UPDATE', (tester) async {
      final s = _DiaryServer();
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(2), 'Page 5');
      await _tapSave(tester);
      await tester.enterText(find.byType(TextField).at(2), 'Page 6');
      await _tapSave(tester);

      expect(_methods(s).where((m) => m == 'POST'), hasLength(1));
      expect(s.requests.last.method, 'PUT');
    });
  });

  group('PUT is a full replace — client-side guard', () {
    testWidgets('clearing one field leaves every other field intact on the '
        'server', (tester) async {
      final s = _DiaryServer()..seed(_existingRow());
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();

      // Empty ONLY the title.
      await tester.enterText(find.text('Fractions'), '');
      await _tapSave(tester);

      // Read back what the (full-replace) server now holds.
      final row = s.rows['e-existing']!;
      expect(row['title'], isNull);
      expect(row['homework'], 'Page 12');
      expect(row['classwork'], 'Worked examples');
      expect(row['note'], 'Bring a ruler');

      // And the wire body carried every key, not just the changed one.
      final body = s.requests.last.data as Map<String, dynamic>;
      expect(body.keys,
          containsAll(['title', 'homework', 'classwork', 'note']));
    });

    test('the draft always serialises all four fields', () {
      const d = DiaryDraft(homework: 'x');
      expect(d.toFields().keys,
          unorderedEquals(['title', 'homework', 'classwork', 'note']));
      expect(d.toFields()['title'], isNull);
    });
  });

  group('409 from a genuine race is a real error', () {
    testWidgets('never swallowed, never reported as saved', (tester) async {
      final s = _DiaryServer()..raceOnPost = true;
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(2), 'Page 5');
      await _tapSave(tester);

      await tester.scrollUntilVisible(find.text('Reload'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('was NOT saved'), findsOneWidget);
      expect(find.text('Reload'), findsOneWidget);
      expect(find.text('Saved.'), findsNothing);
      // The teacher's text survives the failure.
      expect(find.text('Page 5'), findsOneWidget);
    });
  });

  group('States', () {
    testWidgets('load error is an error, not "no entry yet"', (tester) async {
      final s = _DiaryServer()..failGet = true;
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('No diary written'), findsNothing);
      expect(find.text('Save'), findsNothing);
    });

    testWidgets('unreachable → the offline state', (tester) async {
      final s = _DiaryServer()..unreachable = true;
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();
      expect(find.text('You are offline'), findsOneWidget);
      expect(find.textContaining('No diary written'), findsNothing);
    });

    testWidgets('loading shows no form yet', (tester) async {
      _tall(tester);
      final s = _DiaryServer();
      await tester.pumpWidget(_host(_editor(s)));
      expect(find.text('Save'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('a blank NEW entry cannot be saved', (tester) async {
      final s = _DiaryServer();
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Save'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(s.requests.where((r) => r.method != 'GET'), isEmpty);
    });
  });

  group('Shared entry', () {
    testWidgets('someone else wrote it → "Last saved by" strip',
        (tester) async {
      final s = _DiaryServer()..seed(_existingRow(author: 'Bilal Ahmed'));
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Last saved by Bilal Ahmed'), findsOneWidget);
    });

    testWidgets('my own entry → no strip', (tester) async {
      final s = _DiaryServer()..seed(_existingRow());
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Last saved by'), findsNothing);
    });
  });

  group('Repository', () {
    test('findExisting matches on subject, including null subject', () async {
      final s = _DiaryServer()
        ..seed({..._existingRow(), 'id': 'a', 'subjectId': null})
        ..seed({..._existingRow(), 'id': 'b'});
      final repo = _repo(s);
      expect((await repo.findExisting(_key))!.id, 'b');
      expect(
        (await repo.findExisting(
                DiaryKey(sectionId: _sec, subjectId: null, date: _date)))!
            .id,
        'a',
      );
    });

    test('mapper marks a connection failure as unreachable', () {
      final err = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      );
      expect(mapDioError(err).unreachable, isTrue);
    });

    test('TimetablePeriod carries subjectId (the diary key needs it)', () {
      final p = TimetablePeriod.fromJson(
          {'periodName': 'P2', 'sectionId': 's', 'subjectId': 'sub'});
      expect(p.subjectId, 'sub');
    });
  });

  group('Student (sectionId blocker)', () {
    testWidgets('Today and Timetable show "not available yet", no retry',
        (tester) async {
      await tester.pumpWidget(
          _host(const StudentTimetableUnavailable(title: 'Timetable')));
      expect(find.text('Timetable is not available yet'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    test('student destinations never include the teacher Today', () {
      final ids = buildStudentDestinations(
        onSignOut: () async {},
        institutionCode: null,
      ).map((d) => d.id);
      expect(ids, ['today', 'timetable', 'more']);
    });
  });

  group('Layout', () {
    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('diary + student screens: no overflow at $width, 2×, RTL',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final s = _DiaryServer()..seed(_existingRow(author: 'Bilal Ahmed'));
        await tester.pumpWidget(
            _host(_editor(s), textScale: 2, dir: TextDirection.rtl));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(_host(
          const StudentTimetableUnavailable(title: 'Today'),
          textScale: 2,
          dir: TextDirection.rtl,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reduced motion: editor settles without animation',
        (tester) async {
      _tall(tester);
      final s = _DiaryServer();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(role: AppRole.teacher),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _editor(s),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('screen reader: multi-line fields are labelled',
        (tester) async {
      final handle = tester.ensureSemantics();
      final s = _DiaryServer();
      await tester.pumpWidget(_host(_editor(s)));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Homework'), findsWidgets);
      handle.dispose();
    });
  });
}
