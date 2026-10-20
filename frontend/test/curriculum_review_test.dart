import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/academics/data/academics_repository.dart';
import 'package:smartems/features/academics/domain/academic_models.dart';
import 'package:smartems/features/academics/presentation/curriculum_review_screen.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/core/widgets/confirm_dialog.dart';

void main() {
  late Dio dio;
  late List<RequestOptions> writes;
  late bool deny;
  late List<Map<String, dynamic>> history;
  setUp(() {
    writes = [];
    deny = false;
    history = [];
    dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          if (deny) {
            h.reject(
              DioException(
                requestOptions: r,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: r,
                  statusCode: 403,
                  data: {'message': 'Current access denied'},
                ),
              ),
            );
            return;
          }
          if (r.method != 'GET') writes.add(r);
          h.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: jsonEncode(
                r.method == 'GET' ? history : <String, dynamic>{},
              ),
            ),
          );
        },
      ),
    );
  });
  Widget host({
    bool publisher = false,
    bool edit = false,
    String status = 'proposed',
  }) => MaterialApp(
    theme: AppTheme.light(role: AppRole.admin),
    home: CurriculumReviewScreen(
      repository: AcademicsRepository(dio),
      chapter: Chapter(
        id: 'chapter',
        name: 'Synthetic chapter',
        sortOrder: 0,
        topics: const [
          Topic(
            id: 'topic',
            name: 'Reviewed topic',
            sortOrder: 0,
            expectedPeriodCount: null,
          ),
        ],
        canPublish: publisher,
        canEdit: edit,
        status: status,
      ),
    ),
  );
  testWidgets('teacher cannot see publish or reject controls', (t) async {
    await t.pumpWidget(host(edit: true));
    await t.pumpAndSettle();
    expect(find.text('Save draft name'), findsOneWidget);
    expect(find.text('Publish reviewed version'), findsNothing);
    expect(find.text('Reject draft'), findsNothing);
    expect(writes, isEmpty);
  });
  testWidgets(
    'publication requires reason and sends only explicitly reviewed topics',
    (t) async {
      await t.pumpWidget(host(publisher: true));
      await t.pumpAndSettle();
      final button = find.widgetWithText(
        AppButton,
        'Publish reviewed version',
      );
      expect(t.widget<AppButton>(button).onPressed, isNull);
      await t.enterText(
        find.byType(TextField),
        'Reviewed against approved scheme',
      );
      await t.pump();
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byType(ConfirmDialog), matching: find.textContaining('cannot be edited')), findsOneWidget);
      await t.tap(find.byKey(const Key('confirm-ok')));
      await t.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single.data, {
        'expectedPreviousVersion': null,
        'topicIds': ['topic'],
        'adopt': false,
        'reason': 'Reviewed against approved scheme',
      });
      expect(
        find.text(
          'Saved. Return to the syllabus to refresh available actions.',
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets('version history is visible but teacher cannot adopt', (t) async {
    history = [
      {
        'id': 'v1',
        'version': 1,
        'adopted': false,
        'approver_id': 'independent-admin',
        'published_at': '2026-10-16',
        'content_hash': 'synthetic-hash',
        'reason': 'Approved',
        'content': {'name': 'Original'},
      },
    ];
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.text('Version 1 - Published'), findsOneWidget);
    expect(find.text('Fingerprint: synthetic-ha'), findsOneWidget);
    expect(find.text('Adopt version'), findsNothing);
  });
  testWidgets(
    'revoked publication access shows error without success or repeat submission',
    (t) async {
      await t.pumpWidget(host(publisher: true));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Reviewed');
      await t.pump();
      deny = true;
      final button = find.widgetWithText(
        AppButton,
        'Publish reviewed version',
      );
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirm-ok')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('curriculum-error')), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
      expect(
        find.text(
          'Saved. Return to the syllabus to refresh available actions.',
        ),
        findsNothing,
      );
      expect(writes, isEmpty);
    },
  );
  testWidgets('cancelling the publish confirmation sends nothing', (t) async {
    await t.pumpWidget(host(publisher: true));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Reviewed');
    await t.pump();
    final button = find.widgetWithText(AppButton, 'Publish reviewed version');
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('confirm-cancel')));
    await t.pumpAndSettle();
    expect(writes, isEmpty);
    expect(find.text('Saved. Return to the syllabus to refresh available actions.'), findsNothing);
  });
  testWidgets('empty history shows an empty state and meets guidelines', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(publisher: true));
    await t.pumpAndSettle();
    expect(find.text('No published versions yet'), findsOneWidget);
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(t, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
  testWidgets('DEF-14: a published chapter offers no review/publish panel', (t) async {
    await t.pumpWidget(host(publisher: true, status: 'active'));
    await t.pumpAndSettle();
    expect(find.text('Review and publish'), findsNothing);
    expect(find.text('Publish reviewed version'), findsNothing);
    expect(find.text('Create draft revision'), findsOneWidget);
    // Feedback for the remaining actions is still visible without the panel.
    await t.tap(find.text('Create draft revision'));
    await t.pumpAndSettle();
    expect(find.text('Saved. Return to the syllabus to refresh available actions.'), findsOneWidget);
  });
  testWidgets('DEF-15: a version shows chapter and topic names, never the raw record', (t) async {
    history = [
      {
        'id': 'pub-1', 'version': 1, 'adopted': false, 'reason': 'Board outline',
        'published_at': '2026-10-18T09:00:00Z', 'approver_id': 'approver-uuid',
        'content_hash': 'abcdef0123456789abcdef',
        'content': {
          'chapter': {'name': 'Synthetic chapter', 'tenant_id': 'tenant-uuid'},
          'topics': [{'name': 'Reviewed topic', 'tenant_id': 'tenant-uuid'}],
        },
      },
    ];
    await t.pumpWidget(host(publisher: true, status: 'active'));
    await t.pumpAndSettle();
    expect(find.text('Chapter: Synthetic chapter'), findsOneWidget);
    expect(find.text('Topics: Reviewed topic'), findsOneWidget);
    expect(find.text('Fingerprint: abcdef012345'), findsOneWidget);
    expect(find.textContaining('tenant-uuid'), findsNothing);
    expect(find.textContaining('approver-uuid'), findsNothing);
  });
  testWidgets('DEF-16: the reason field is named only by its own label', (t) async {
    final handle = t.ensureSemantics();
    await t.pumpWidget(host(publisher: true));
    await t.pumpAndSettle();
    final node = t.getSemantics(find.descendant(of: find.byKey(const Key('curriculum-reason')), matching: find.byType(TextField)));
    expect(node.label, contains('Review reason'));
    expect(node.label, isNot(contains('Review and publish')));
    expect(node.label, isNot(contains('Select exactly')));
    handle.dispose();
  });
}
