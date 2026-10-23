import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/admin/data/institution_admin_repository.dart';
import 'package:smartems/features/admin/presentation/institution_admins_screen.dart';

/// ADR-007 / Doc 21 Owner-only Institution Admin screens against a fake adapter
/// answering like the real routes.
class _Server implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  List<Map<String, dynamic>> admins = [
    {'userId': 'u-admin', 'username': 'sana.admin', 'since': '2026-10-01'},
  ];
  int? approvalStatus;
  String approvalMessage = 'A fresh approval for this action is required';
  int? appointStatus;
  String appointMessage = 'Only the institution owner can manage institution admins';

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    final path = o.uri.path;
    if (o.method == 'GET' && path == '/api/institution/admins') return _raw(200, jsonEncode(admins));
    if (o.method == 'GET' && path == '/api/staff') {
      return _raw(200, jsonEncode({'content': [
        {'userId': 'u-admin', 'firstName': 'Sana', 'lastName': 'Admin'},
        {'userId': 'u-teacher', 'firstName': 'Bilal', 'lastName': 'Teacher'},
        {'userId': null, 'firstName': 'No', 'lastName': 'Login'},
      ]}));
    }
    if (path == '/auth/mfa/approvals') {
      if (approvalStatus != null) return _raw(approvalStatus!, jsonEncode({'message': approvalMessage}));
      return _raw(201, '{"approvalId":"ap-1"}');
    }
    if (o.method == 'POST' && path == '/api/institution/admins') {
      if (appointStatus != null) return _raw(appointStatus!, jsonEncode({'message': appointMessage}));
      admins = [...admins, {'userId': 'u-teacher', 'username': 'bilal.teacher'}];
      return _raw(200, '{"status":"appointed"}');
    }
    if (o.method == 'DELETE' && path.startsWith('/api/institution/admins/')) {
      admins = admins.where((a) => !path.endsWith(a['userId'] as String)).toList();
      return _raw(204, '');
    }
    return _raw(404, '{"message":"not found"}');
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _raw(int status, String json) => ResponseBody.fromBytes(utf8.encode(json), status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

Future<_Server> _pump(WidgetTester tester) async {
  final server = _Server();
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server;
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(role: AppRole.admin),
    home: InstitutionAdminsScreen(repository: InstitutionAdminRepository(dio)),
  ));
  await tester.pumpAndSettle();
  return server;
}

Future<void> _code(WidgetTester tester, String code) async {
  await tester.enterText(find.descendant(of: find.byKey(const Key('institution-admin-code')), matching: find.byType(TextField)), code);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('institution-admin-target')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists current admins; candidates exclude admins and login-less staff', (tester) async {
    await _pump(tester);
    expect(find.text('sana.admin'), findsOneWidget);
    await tester.tap(find.byKey(const Key('institution-admin-target')));
    await tester.pumpAndSettle();
    expect(find.text('Bilal Teacher'), findsWidgets);
    expect(find.text('Sana Admin'), findsNothing);
    expect(find.text('No Login'), findsNothing);
  });

  testWidgets('appoint sends nothing without a target and a code', (tester) async {
    final server = await _pump(tester);
    await tester.tap(find.byKey(const Key('institution-admin-appoint')));
    await tester.pumpAndSettle();
    await _choose(tester, 'Bilal Teacher');
    await tester.tap(find.byKey(const Key('institution-admin-appoint')));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
  });

  testWidgets('appointment sends a target-specific approval first, then the appointment', (tester) async {
    final server = await _pump(tester);
    await _choose(tester, 'Bilal Teacher');
    await _code(tester, '123456');
    await tester.tap(find.byKey(const Key('institution-admin-appoint')));
    await tester.pumpAndSettle();
    final writes = server.requests.where((r) => r.method != 'GET').toList();
    expect(writes.map((r) => r.path), ['/auth/mfa/approvals', '/api/institution/admins']);
    expect(writes.first.data, {'action': 'INSTITUTION_ADMIN_APPOINT', 'targetId': 'u-teacher', 'code': '123456'});
    expect(writes.last.data, {'userId': 'u-teacher'});
    expect(find.textContaining('now have Institution Admin access'), findsOneWidget);
    expect(find.text('bilal.teacher'), findsOneWidget);
  });

  testWidgets('a refused approval stops before the appointment and is shown', (tester) async {
    final server = await _pump(tester);
    server.approvalStatus = 403;
    await _choose(tester, 'Bilal Teacher');
    await _code(tester, '000000');
    await tester.tap(find.byKey(const Key('institution-admin-appoint')));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method == 'POST' && r.path == '/api/institution/admins'), isEmpty);
    expect(find.textContaining('fresh approval for this action is required'), findsOneWidget);
  });

  testWidgets('a non-owner refusal from the server is shown verbatim', (tester) async {
    final server = await _pump(tester);
    server.appointStatus = 403;
    await _choose(tester, 'Bilal Teacher');
    await _code(tester, '123456');
    await tester.tap(find.byKey(const Key('institution-admin-appoint')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Only the institution owner can manage institution admins'), findsOneWidget);
    expect(find.text('bilal.teacher'), findsNothing);
  });

  testWidgets('removal needs a code and a confirmation, then approves that admin only', (tester) async {
    final server = await _pump(tester);
    // Each row's button says whose access it removes (screen readers).
    expect(find.bySemanticsLabel('Remove sana.admin'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove-u-admin')));
    await tester.pumpAndSettle();
    expect(find.textContaining('fresh authenticator code first'), findsOneWidget);
    expect(server.requests.where((r) => r.method != 'GET'), isEmpty);
    await _code(tester, '654321');
    await tester.tap(find.byKey(const Key('remove-u-admin')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method != 'GET'), isEmpty, reason: 'cancel sends nothing');
    await tester.tap(find.byKey(const Key('remove-u-admin')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    final writes = server.requests.where((r) => r.method != 'GET').toList();
    expect(writes.first.data, {'action': 'INSTITUTION_ADMIN_REMOVE', 'targetId': 'u-admin', 'code': '654321'});
    expect(writes.last.method, 'DELETE');
    expect(writes.last.path, '/api/institution/admins/u-admin');
    expect(find.textContaining('signed out'), findsOneWidget);
  });
}

