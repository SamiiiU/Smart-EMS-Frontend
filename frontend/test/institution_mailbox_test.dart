import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart';
import 'package:smartems/features/admin/presentation/institution_mailbox_screen.dart';

class MailboxAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  String? status;
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<List<int>>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(request);
    Object data;
    int code = 200;
    if (request.path.startsWith('/api/workflow-jobs/')) {
      data = {
        'status': 'completed',
        'result': {'connectionVerified': true},
      };
    } else if (request.path.endsWith('/verify')) {
      status = 'verified';
      code = 202;
      data = {'jobId': 'fixture-job'};
    } else {
      if (request.method == 'POST') {
        status = request.path.endsWith('/actions') ? 'enabled' : 'draft';
      }
      data = status == null
          ? {'configured': false}
          : {
              'id': 'fixture-mailbox',
              'host': 'smtp.gmail.com',
              'port': 587,
              'ssl': false,
              'from_email': 'fixture@example.test',
              'display_name': 'Fixture Academy',
              'status': status,
            };
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      code,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets(
    'password is write-only, Gmail spaces removed, verification precedes enabling',
    (tester) async {
      final adapter = MailboxAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(role: AppRole.admin),
          home: InstitutionMailboxScreen(dio: dio),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Fixture Academy');
      await tester.enterText(fields.at(1), 'fixture@example.test');
      await tester.ensureVisible(fields.at(3));
      await tester.enterText(fields.at(3), 'abcd efgh ijkl mnop');
      final passwordField = tester.widget<TextFormField>(fields.at(3));
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: fields.at(3),
                matching: find.byType(TextField),
              ),
            )
            .obscureText,
        isTrue,
      );
      await tester.ensureVisible(find.text('Save mailbox'));
      await tester.tap(find.text('Save mailbox'));
      await tester.pumpAndSettle();
      final save = adapter.requests.singleWhere(
        (request) => request.method == 'POST',
      );
      expect((save.data as Map)['password'], 'abcdefghijklmnop');
      expect((save.data as Map).containsKey('from'), isFalse);
      expect(save.headers['Idempotency-Key'], isNotEmpty);
      expect(passwordField.controller!.text, isEmpty);
      expect(find.text('Enable sending'), findsNothing);
      await tester.ensureVisible(find.text('Verify connection'));
      await tester.tap(find.text('Verify connection'));
      await tester.pumpAndSettle();
      expect(find.text('Enable sending'), findsOneWidget);
      await tester.ensureVisible(find.text('Enable sending'));
      await tester.tap(find.text('Enable sending'));
      await tester.pumpAndSettle();
      expect(find.text('Pause sending'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
