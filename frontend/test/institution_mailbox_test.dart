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

  Future<MailboxAdapter> open(WidgetTester tester, {String? status, int? failSave}) async {
    final adapter = failSave == null ? (MailboxAdapter()..status = status) : (_FailingSave(failSave)..status = status);
    final dio = Dio()..httpClientAdapter = adapter;
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(role: AppRole.admin), home: InstitutionMailboxScreen(dio: dio)));
    await tester.pumpAndSettle();
    return adapter;
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save mailbox'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save mailbox'));
    await tester.pumpAndSettle();
  }

  testWidgets('Form validation kept: empty save shows every required error and sends nothing', (tester) async {
    final adapter = await open(tester);
    await tester.enterText(find.byType(TextFormField).at(2), ''); // host has a default
    await save(tester);
    expect(find.text('Enter the institution name.'), findsOneWidget);
    expect(find.text('Enter the complete email address.'), findsOneWidget);
    expect(find.text('Enter your outgoing SMTP host.'), findsOneWidget);
    expect(find.text('Enter the mailbox app password.'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('per-keystroke typing, paste and backspace keep the full value', (tester) async {
    await open(tester);
    final name = find.byType(TextFormField).at(0);
    var value = '';
    for (final ch in 'Iqra Academy'.split('')) {
      value += ch;
      await tester.enterText(name, value);
      await tester.pump();
    }
    expect(tester.widget<TextFormField>(name).controller!.text, 'Iqra Academy');
    await tester.enterText(name, 'Iqra Academy Lahore'); // paste
    await tester.pump();
    await tester.enterText(name, 'Iqra Academy Lahor'); // backspace
    await tester.pump();
    expect(tester.widget<TextFormField>(name).controller!.text, 'Iqra Academy Lahor');
  });

  testWidgets('status is plain language and a save confirms visibly', (tester) async {
    final adapter = await open(tester, status: 'verified');
    expect(find.textContaining('Verified. Sending is off until you enable it.'), findsOneWidget);
    expect(find.textContaining('status: verified'), findsNothing);
    await tester.enterText(find.byType(TextFormField).at(3), 'app-password');
    await save(tester);
    expect(find.text('Mailbox settings saved.'), findsOneWidget);
    expect(adapter.requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  testWidgets('a server refusal is shown as the server message and nothing is claimed saved', (tester) async {
    await open(tester, failSave: 400);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Fixture Academy');
    await tester.enterText(fields.at(1), 'fixture@example.test');
    await tester.enterText(fields.at(2), 'smtp.unapproved.test');
    await tester.enterText(fields.at(3), 'app-password');
    await save(tester);
    expect(find.text('SMTP host is not approved'), findsOneWidget);
    expect(find.text('Mailbox settings saved.'), findsNothing);
  });

  testWidgets('Disconnect asks first; cancelling sends nothing', (tester) async {
    final adapter = await open(tester, status: 'enabled');
    await tester.ensureVisible(find.text('Disconnect'));
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(find.text('Disconnect institution mailbox?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-cancel')));
    await tester.pumpAndSettle();
    expect(adapter.requests.where((r) => r.method == 'POST'), isEmpty);
  });
}

class _FailingSave extends MailboxAdapter {
  _FailingSave(this.code);
  final int code;
  @override
  Future<ResponseBody> fetch(RequestOptions request, Stream<List<int>>? stream, Future<void>? cancel) async {
    if (request.method == 'POST' && request.path == '/api/institution-mailbox') {
      requests.add(request);
      return ResponseBody.fromString(jsonEncode({'message': 'SMTP host is not approved'}), code,
          headers: {'content-type': ['application/json']});
    }
    return super.fetch(request, stream, cancel);
  }
}
