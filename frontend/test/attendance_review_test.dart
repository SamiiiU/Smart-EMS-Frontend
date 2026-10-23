import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/attendance/data/attendance_review_repository.dart';
import 'package:smartems/features/attendance/presentation/attendance_review_screen.dart';

class _Server implements HttpClientAdapter {
  _Server(this.responder);
  final ResponseBody Function(RequestOptions o) responder;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    return responder(o);
  }

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

void main() {
  testWidgets(
    'reviewer must give a reason; the decision is sent and the list reloads',
    (tester) async {
      var decided = false;
      final server = _Server((o) {
        if (o.method == 'GET') {
          return _json(200, {
            'content': decided
                ? []
                : [
                    {
                      'id': 'r1',
                      'firstName': 'Bilal',
                      'lastName': 'Ahmed',
                      'attendanceDate': '2026-10-10',
                      'submittedStatus': 'absent',
                      'currentServerStatus': 'present',
                      'reason': 'CONFLICT',
                      'receivedAt': '2026-10-10T09:00:00Z',
                    },
                  ],
            'totalElements': decided ? 0 : 1,
          });
        }
        decided = true;
        return _json(200, {'reviewId': 'r1', 'state': 'rejected'});
      });
      final repo = AttendanceReviewRepository(
        Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
          ..httpClientAdapter = server,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: AttendanceReviewScreen(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Teacher marked absent; office record present'),
        findsOneWidget,
      );

      await tester.tap(find.text('Keep office record'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(TextButton, 'Confirm');
      expect(
        tester.widget<TextButton>(confirm).onPressed,
        isNull,
        reason: 'a reason is mandatory',
      );
      await tester.enterText(find.byType(TextField), 'Student was present');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();

      final post = server.requests.firstWhere((r) => r.method == 'POST');
      expect(post.path, '/api/attendance/reviews/r1/reject');
      expect((post.data as Map)['reason'], 'Student was present');
      expect(find.text('Nothing is waiting for review.'), findsOneWidget);
    },
  );
}
