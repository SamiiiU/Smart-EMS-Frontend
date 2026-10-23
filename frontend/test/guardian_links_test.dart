import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/admin/presentation/guardian_links_screen.dart';

void main() {
  late Dio dio;
  late bool denied;
  late Map<String, dynamic> row;
  late List<Map<String, dynamic>> reviews;
  setUp(() {
    denied = false;
    reviews = [];
    row = {
      'id': 'link',
      'first_name': 'Synthetic',
      'last_name': 'Contact',
      'link_status': 'unreviewed',
      'is_emergency_contact': true,
      'verified_at': null,
      'can_view_academic': false,
      'can_view_attendance': false,
      'can_view_finance': false,
      'can_view_documents': false,
      'can_receive_communication': false,
    };
    dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (denied) {
            handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: request,
                  statusCode: 403,
                  data: {'message': 'Access denied'},
                ),
              ),
            );
            return;
          }
          if (request.method == 'POST') {
            reviews.add(Map<String, dynamic>.from(request.data as Map));
          }
          handler.resolve(
            Response(
              requestOptions: request,
              statusCode: 200,
              data: request.method == 'GET'
                  ? [row]
                  : {'id': 'link', 'linkStatus': 'active'},
            ),
          );
        },
      ),
    );
  });
  Widget host() => MaterialApp(
    theme: AppTheme.light(role: AppRole.admin),
    home: GuardianLinksScreen(
      repository: AdminRepository(dio),
      studentId: 'child',
    ),
  );
  testWidgets(
    'pending emergency relationship displays unverified and no automatic categories',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      expect(find.text('Synthetic Contact - unreviewed'), findsOneWidget);
      expect(find.text('Verified: Not verified'), findsOneWidget);
      expect(find.text('Emergency contact'), findsOneWidget);
      expect(reviews, isEmpty);
    },
  );
  testWidgets('verified contact-only and revoked states stay distinct', (
    tester,
  ) async {
    row['link_status'] = 'active';
    row['verified_at'] = '2026-10-16T00:00:00Z';
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Contact only - no protected browsing'), findsOneWidget);
    row['link_status'] = 'revoked';
    await tester.tap(find.text('Refresh relationships'));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic Contact - revoked'), findsOneWidget);
    expect(find.text('Review relationship'), findsNothing);
  });
  testWidgets('denied staff cannot see relationship names or review actions', (
    tester,
  ) async {
    denied = true;
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('Synthetic Contact - unreviewed'), findsNothing);
    expect(find.text('Review relationship'), findsNothing);
  });
  testWidgets(
    'review collects evidence and sends explicit false grants rather than blanket access',
    (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review relationship'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Synthetic evidence C11');
      await tester.tap(find.text('Record review'));
      await tester.pumpAndSettle();
      expect(reviews, hasLength(1));
      expect(reviews.single['reason'], 'Synthetic evidence C11');
      expect(
        (reviews.single['categories'] as Map).values.every(
          (value) => value == false,
        ),
        isTrue,
      );
    },
  );
}
