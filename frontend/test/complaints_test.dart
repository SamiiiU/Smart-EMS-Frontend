import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/complaints/data/complaints_repository.dart';
import 'package:smartems/features/complaints/domain/complaint_models.dart';
import 'package:smartems/features/complaints/presentation/admin_complaints_screen.dart';
import 'package:smartems/features/complaints/presentation/complaint_detail_screen.dart';
import 'package:smartems/features/complaints/presentation/complaint_row.dart';
import 'package:smartems/features/complaints/presentation/my_complaints_screen.dart';
import 'package:smartems/features/complaints/presentation/raise_complaint_screen.dart';

/// A stub of the complaints endpoints with this backend's REAL behaviour —
/// including the two guarantees that decide whether these screens ship at
/// all: internal comments are filtered for a complainant, and an anonymous
/// complaint carries no raiser id for ANYONE.
class _ComplaintServer implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  String complaintsJson = '[]';
  String detailJson = '{}';

  /// What the CALLER receives. The live backend filters `is_internal`
  /// comments out of a complainant's response, so a complainant's stub
  /// simply does not include them — modelling the server, not the client.
  String commentsJson = '[]';

  /// Whichever role this stub is standing in for.
  bool isAdmin = true;

  Object? lastBody;
  int? failStatus;
  String failMessage = 'Something went wrong';

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    final path = o.uri.path;
    final body = o.data is Map ? (o.data as Map).cast<String, dynamic>() : null;

    if (o.method == 'GET') {
      if (path == '/api/complaints') {
        // Admin only on the live API.
        if (!isAdmin) return _raw(403, '{"message":"Forbidden"}');
        return _raw(200, '{"content":$complaintsJson,"totalElements":1}');
      }
      if (path == '/api/complaints/my') {
        return _raw(200, '{"content":$complaintsJson,"totalElements":1}');
      }
      if (path.endsWith('/comments')) return _raw(200, commentsJson);
      if (path.startsWith('/api/complaints/')) return _raw(200, detailJson);
      if (path == '/api/staff/me') {
        return isAdmin
            ? _raw(403, '{"message":"Forbidden"}')
            : _raw(200, '{"id":"staff-1","campusId":"campus-1"}');
      }
      if (path == '/api/students/me') return _raw(403, '{"message":"no"}');
      if (path == '/api/campuses') {
        return _raw(200, '[{"id":"campus-1","name":"Main"}]');
      }
      if (path == '/api/staff') {
        return _raw(200,
            '{"content":[{"id":"staff-1","firstName":"Ayesha","lastName":"Khan"}]}');
      }
      if (path == '/api/students') return _raw(200, '{"content":[]}');
      return _raw(404, '{"message":"no route"}');
    }

    if (failStatus != null) {
      final status = failStatus!;
      failStatus = null;
      return _raw(status, '{"message":"$failMessage"}');
    }

    if (o.method == 'POST' && path == '/api/complaints') {
      lastBody = body;
      return _raw(
        201,
        '{"id":"c-1","subject":"${body?['subject']}","category":'
        '"${body?['category']}","priority":"${body?['priority']}",'
        '"status":"open","is_anonymous":${body?['isAnonymous']},'
        // The live API stores NO raiser id for an anonymous complaint.
        '"raised_by_user_id":${body?['isAnonymous'] == true ? 'null' : '"u-1"'},'
        '"created_at":"2026-09-27T00:00:00Z"}',
      );
    }
    if (o.method == 'POST' && path.endsWith('/comments')) {
      lastBody = body;
      return _raw(201, '{"id":"cm-1","isInternal":${body?['isInternal']}}');
    }
    if (o.method == 'PUT') {
      lastBody = body;
      return _raw(200, '{"ok":true}');
    }
    return _raw(404, '{"message":"no route"}');
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

typedef _Wired = ({
  Dio dio,
  _ComplaintServer server,
  ComplaintsRepository repo,
});

_Wired _wire() {
  final server = _ComplaintServer();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server;
  return (dio: dio, server: server, repo: ComplaintsRepository(dio));
}

Widget _host(Widget child, {bool dark = false}) => MaterialApp(
      theme: dark
          ? AppTheme.dark(role: AppRole.admin)
          : AppTheme.light(role: AppRole.admin),
      home: child,
    );

const _namedJson = '{"id":"c-1","subject":"Broken fan","category":"facility",'
    '"priority":"high","status":"open","is_anonymous":false,'
    '"raised_by_user_id":"u-1","description":"The fan does not work",'
    '"created_at":"2026-09-20T00:00:00Z","due_by":"2026-09-22"}';

const _anonJson = '{"id":"c-2","subject":"A worry","category":"academic",'
    '"priority":"medium","status":"open","is_anonymous":true,'
    '"raised_by_user_id":null,"description":"Told in confidence",'
    '"created_at":"2026-09-26T00:00:00Z"}';

void main() {
  group('🔴 internal comments never reach a complainant', () {
    testWidgets('a complainant sees only what the server sent them',
        (tester) async {
      final w = _wire();
      w.server.isAdmin = false;
      w.server.detailJson = _namedJson;
      // Exactly what the live backend returns to a complainant: the
      // internal one is ABSENT, not present-and-hidden.
      w.server.commentsJson = '[{"id":"cm-2","body":"We are looking into it",'
          '"is_internal":false,"created_at":"2026-09-21T00:00:00Z"}]';

      await tester.pumpWidget(_host(ComplaintDetailScreen(
        repository: w.repo,
        complaintId: 'c-1',
      )));
      await tester.pumpAndSettle();

      expect(find.text('We are looking into it'), findsOneWidget);
      expect(
        find.textContaining('Internal note'),
        findsNothing,
        reason: 'nothing marked internal may render on a complainant’s view',
      );
    });

    testWidgets('a complainant is never offered the internal toggle',
        (tester) async {
      final w = _wire();
      w.server.isAdmin = false;
      w.server.detailJson = _namedJson;

      await tester.pumpWidget(_host(ComplaintDetailScreen(
        repository: w.repo,
        complaintId: 'c-1',
        // staffControls defaults to false — the complainant's view.
      )));
      await tester.pumpAndSettle();

      expect(find.byType(InternalToggle), findsNothing);
    });

    testWidgets('a staff internal note is marked unmistakably — in WORDS',
        (tester) async {
      final w = _wire();
      w.server.detailJson = _namedJson;
      w.server.commentsJson = '['
          '{"id":"cm-1","body":"Parent is a governor","is_internal":true,'
          '"created_at":"2026-09-21T00:00:00Z"},'
          '{"id":"cm-2","body":"We are looking into it","is_internal":false,'
          '"created_at":"2026-09-21T00:00:00Z"}]';

      await tester.pumpWidget(_host(ComplaintDetailScreen(
        repository: w.repo,
        complaintId: 'c-1',
        staffControls: true,
      )));
      await tester.pumpAndSettle();

      // Not a colour, not an icon alone: the sentence says who cannot see it.
      expect(
        find.text('Internal note — the complainant cannot see this'),
        findsOneWidget,
      );
    });

    testWidgets('the internal toggle states the consequence both ways',
        (tester) async {
      final w = _wire();
      w.server.detailJson = _namedJson;

      await tester.pumpWidget(_host(ComplaintDetailScreen(
        repository: w.repo,
        complaintId: 'c-1',
        staffControls: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('The person who raised this will see your reply.'),
          findsOneWidget);

      await tester.ensureVisible(find.byType(InternalToggle));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        find.text('Staff only. The person who raised this will not see it.'),
        findsOneWidget,
      );
    });

    test('the app never filters comments itself', () async {
      // If the app filtered, a server regression would be invisible. It
      // renders whatever arrives — which is why the widget tests above are
      // about what the SERVER sent.
      final w = _wire();
      w.server.commentsJson = '['
          '{"id":"a","body":"public","is_internal":false,"created_at":"x"},'
          '{"id":"b","body":"internal","is_internal":true,"created_at":"x"}]';

      final comments = await w.repo.loadComments('c-1');
      expect(comments.length, 2);
      expect(comments.where((c) => c.isInternal).length, 1);
    });
  });

  group('🔴 an anonymous complaint exposes no identity', () {
    testWidgets('the admin list shows no raiser for an anonymous complaint',
        (tester) async {
      final w = _wire();
      w.server.complaintsJson = '[$_anonJson]';

      await tester.pumpWidget(_host(AdminComplaintsScreen(
        repository: w.repo,
        admin: AdminRepository(w.dio),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Sent anonymously'), findsOneWidget);
      expect(find.text('Named'), findsNothing);

      // Nothing in the rendered tree carries a user id.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>();
      for (final text in texts) {
        expect(text.contains('u-1'), isFalse,
            reason: 'a raiser id must never reach the screen');
      }
    });

    testWidgets('the detail says a reply cannot reach them', (tester) async {
      final w = _wire();
      w.server.detailJson = _anonJson;

      await tester.pumpWidget(_host(ComplaintDetailScreen(
        repository: w.repo,
        complaintId: 'c-2',
        staffControls: true,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('no record of who raised it'), findsOneWidget);
      expect(find.textContaining('will not reach them'), findsOneWidget);
    });

    test('the model carries no raiser for an anonymous complaint', () {
      final anon = Complaint.fromJson(
          jsonDecode(_anonJson) as Map<String, dynamic>);
      expect(anon.isAnonymous, isTrue);
      expect(anon.raisedByUserId, isNull);
    });

    testWidgets('the raise screen states the cost BEFORE it is chosen',
        (tester) async {
      final w = _wire();
      await tester.pumpWidget(_host(RaiseComplaintScreen(
        repository: w.repo,
        campusId: 'campus-1',
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Write your complaint'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(AnonymityControl));
      await tester.pumpAndSettle();

      expect(find.textContaining('can reply to you'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // The trade, in the same breath as the choice.
      expect(find.textContaining('nobody can reply to you'), findsOneWidget);
      expect(find.textContaining('will not see an update'), findsOneWidget);
    });
  });

  group('raising', () {
    test('only the six accepted categories and three priorities exist', () {
      expect(
        ComplaintCategory.values.map((c) => c.wire),
        ['academic', 'fee', 'transport', 'staff_behaviour', 'facility',
          'other'],
      );
      expect(
        ComplaintPriority.values.map((p) => p.wire),
        ['low', 'medium', 'high'],
      );
    });

    test('`open` is never offered as something to set', () {
      // The backend rejects it: "status must be one of [in_progress,
      // resolved, closed]".
      expect(
        ComplaintStatus.settable.map((s) => s.wire),
        ['in_progress', 'resolved', 'closed'],
      );
      expect(ComplaintStatus.settable.contains(ComplaintStatus.open), isFalse);
    });

    test('the wire body carries the anonymity flag as chosen', () async {
      final w = _wire();
      await w.repo.raise(
        campusId: 'campus-1',
        category: ComplaintCategory.facility,
        subject: 'Broken fan',
        description: 'It does not turn',
        isAnonymous: true,
      );
      final body = w.server.lastBody! as Map;
      expect(body['isAnonymous'], isTrue);
      expect(body['category'], 'facility');
      expect(body['campusId'], 'campus-1');
    });
  });

  group('🔴 a parent cannot raise one, and is told so', () {
    testWidgets('the screen explains rather than offering a dead form',
        (tester) async {
      final w = _wire();
      // A parent: 403 on /api/campuses, and neither /staff/me nor
      // /students/me resolves. Exactly the live behaviour.
      w.server.isAdmin = true; // makes /api/staff/me 403 in this stub
      w.server.complaintsJson = '[]';

      await tester.pumpWidget(_host(MyComplaintsScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('cannot be raised from a parent account yet'),
        findsOneWidget,
      );
      expect(find.text('Raise a complaint'), findsNothing);
    });

    testWidgets('a role that CAN resolve a campus gets the button',
        (tester) async {
      final w = _wire();
      w.server.isAdmin = false; // /api/staff/me returns a campusId
      w.server.complaintsJson = '[]';

      await tester.pumpWidget(_host(MyComplaintsScreen(repository: w.repo)));
      await tester.pumpAndSettle();

      expect(find.text('Raise a complaint'), findsOneWidget);
    });

    test('resolveCampusId returns null when no endpoint carries one',
        () async {
      final w = _wire();
      w.server.isAdmin = true; // both /me endpoints refuse
      expect(await w.repo.resolveCampusId(), isNull);
    });
  });

  group('the admin worklist is ordered by what needs doing (D-15)', () {
    Complaint c(
      String subject, {
      required String status,
      String? assigned,
      String? due,
      String created = '2026-09-25T00:00:00Z',
    }) =>
        Complaint.fromJson({
          'id': subject,
          'subject': subject,
          'category': 'other',
          'priority': 'medium',
          'status': status,
          'is_anonymous': false,
          'created_at': created,
          'assigned_to_staff_id': assigned,
          'due_by': due,
        });

    test('overdue, then unassigned, then open, then finished', () {
      final today = DateTime(2026, 9, 27);
      final sorted = sortForAdmin([
        c('Finished', status: 'resolved'),
        c('Open and assigned', status: 'in_progress', assigned: 's1'),
        c('Unassigned', status: 'open'),
        c('Overdue', status: 'open', assigned: 's1', due: '2026-09-20'),
      ], today);

      expect(
        sorted.map((x) => x.subject),
        ['Overdue', 'Unassigned', 'Open and assigned', 'Finished'],
      );
    });

    test('a finished complaint is never overdue, however old', () {
      final today = DateTime(2026, 9, 27);
      expect(
        c('x', status: 'resolved', due: '2020-01-01').isOverdue(today),
        isFalse,
      );
    });

    test('the complainant’s own list puts unresolved first', () {
      final today = DateTime(2026, 9, 27);
      final sorted = sortForOwner([
        c('Done', status: 'resolved'),
        c('Waiting', status: 'open'),
      ], today);
      expect(sorted.first.subject, 'Waiting');
    });
  });

  group('rendering', () {
    testWidgets('an overdue row says so in words, not just a colour',
        (tester) async {
      await tester.pumpWidget(_host(ComplaintRow(
        complaint: Complaint.fromJson(
            jsonDecode(_namedJson) as Map<String, dynamic>),
        today: DateTime(2026, 9, 27),
        showRaiser: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.text('High priority'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('every complaints screen renders in ${dark ? 'dark' : 'light'}',
          (tester) async {
        final w = _wire();
        w.server.complaintsJson = '[$_namedJson,$_anonJson]';
        w.server.detailJson = _namedJson;
        w.server.commentsJson = '[{"id":"cm-1","body":"note",'
            '"is_internal":true,"created_at":"x"}]';

        final screens = <String, Widget>{
          'mine': MyComplaintsScreen(repository: w.repo, campusId: 'c'),
          'admin': AdminComplaintsScreen(
            repository: w.repo,
            admin: AdminRepository(w.dio),
          ),
          'detail': ComplaintDetailScreen(
            repository: w.repo,
            complaintId: 'c-1',
            staffControls: true,
          ),
          'raise':
              RaiseComplaintScreen(repository: w.repo, campusId: 'campus-1'),
        };

        for (final entry in screens.entries) {
          await tester.pumpWidget(_host(entry.value, dark: dark));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: entry.key);
        }
      });
    }

    for (final width in [360.0, 768.0, 1366.0]) {
      testWidgets('no complaints screen overflows at ${width.toInt()}px',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final w = _wire();
        w.server.complaintsJson = '[$_namedJson,$_anonJson]';
        w.server.detailJson = _namedJson;

        for (final screen in <Widget>[
          MyComplaintsScreen(repository: w.repo, campusId: 'c'),
          AdminComplaintsScreen(
            repository: w.repo,
            admin: AdminRepository(w.dio),
          ),
          ComplaintDetailScreen(
            repository: w.repo,
            complaintId: 'c-1',
            staffControls: true,
          ),
        ]) {
          await tester.pumpWidget(_host(screen));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('a complaint row carries its state in its semantics label',
        (tester) async {
      final w = _wire();
      w.server.complaintsJson = '[$_namedJson]';

      await tester.pumpWidget(_host(MyComplaintsScreen(
        repository: w.repo,
        campusId: 'c',
      )));
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsLabel(RegExp('Broken fan.*Open.*overdue')),
        findsOneWidget,
      );
    });
  });
}
