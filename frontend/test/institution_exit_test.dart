import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/features/admin/presentation/institution_exit_screen.dart';

void main() {
  late Dio dio;
  late List<Map<String, dynamic>> requests;
  late bool denied;
  late String state;
  setUp(() {
    requests = [];
    denied = false;
    state = 'active';
    dio = Dio(BaseOptions(baseUrl: 'https://fixture.invalid'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          if (denied) {
            h.reject(
              DioException(
                requestOptions: r,
                type: DioExceptionType.badResponse,
                response: Response(requestOptions: r, statusCode: 403),
              ),
            );
            return;
          }
          if (r.method == 'POST') {
            requests.add(Map<String, dynamic>.from(r.data as Map));
            state = 'export_only';
          }
          h.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: {
                'state': state,
                'activeHolds': 0,
                'blockers': ['LEGALLY_APPROVED_RETENTION_SCHEDULE_MISSING'],
                'productionPurgeEnabled': false,
              },
            ),
          );
        },
      ),
    );
  });
  Widget host() => MaterialApp(home: InstitutionExitScreen(dio: dio));
  testWidgets('owner must enter reason and explicitly confirm read-only exit', (
    t,
  ) async {
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    final button = find.widgetWithText(TextButton, 'Request read-only exit');
    await t.ensureVisible(button);
    expect(t.widget<TextButton>(button).onPressed, isNull);
    await t.enterText(find.byType(TextField), 'Synthetic owner request');
    await t.pump();
    await t.ensureVisible(find.byType(CheckboxListTile));
    await t.tap(find.byType(CheckboxListTile));
    await t.pump();
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(requests.single['reason'], 'Synthetic owner request');
    expect(requests.single['operationId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(find.text('State: export_only'), findsOneWidget);
    expect(find.text('Download partial data snapshot'), findsOneWidget);
  });
  testWidgets('restricted state exposes no request or export action', (
    t,
  ) async {
    state = 'restricted';
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(find.text('State: restricted'), findsOneWidget);
    expect(find.text('Request read-only exit'), findsNothing);
    expect(find.text('Download partial data snapshot'), findsNothing);
    expect(requests, isEmpty);
  });
  testWidgets('unauthorized actor sees denial and no mutation form', (t) async {
    denied = true;
    await t.pumpWidget(host());
    await t.pumpAndSettle();
    expect(
      find.text('Institution owner access required or service unavailable.'),
      findsOneWidget,
    );
    expect(find.text('Request read-only exit'), findsNothing);
    expect(requests, isEmpty);
  });
}
