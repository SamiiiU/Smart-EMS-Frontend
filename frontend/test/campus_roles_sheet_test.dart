import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/campus_context.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/app_button.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/admin/presentation/campus_roles_sheet.dart';

class _Server implements HttpClientAdapter {
  _Server(this.respond);
  final ResponseBody Function(RequestOptions o) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requests.add(o);
    return respond(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(utf8.encode(jsonEncode(body)), status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

const _campuses = [
  CampusOption(id: 'ca', name: 'Campus A', permissions: {}),
  CampusOption(id: 'cb', name: 'Campus B', permissions: {}),
];

Widget _host(_Server server) => MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: Scaffold(
        body: CampusRolesSheet(
          repository: AdminRepository(Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = server),
          userId: 'u1',
          personName: 'Ayesha Khan',
          campuses: _campuses,
        ),
      ),
    );

void main() {
  testWidgets('lists campus roles, removes one only after confirmation', (tester) async {
    var grants = [
      {'grantId': 'g1', 'campusId': 'ca', 'campusName': 'Campus A', 'role': 'teacher'},
    ];
    final server = _Server((o) {
      if (o.method == 'DELETE') {
        grants = [];
        return _json(204, {});
      }
      return _json(200, grants);
    });
    await tester.pumpWidget(_host(server));
    await tester.pumpAndSettle();
    expect(find.text('Teacher'), findsWidgets);
    expect(find.text('Campus A'), findsWidgets);
    await tester.tap(find.byTooltip('Remove Teacher at Campus A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.requests.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.tap(find.byTooltip('Remove Teacher at Campus A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-remove-campus-role')));
    await tester.pumpAndSettle();
    final delete = server.requests.singleWhere((r) => r.method == 'DELETE');
    expect(delete.path, '/api/users/u1/campus-grants/g1');
    expect(find.text('No campus roles yet.'), findsOneWidget);
    expect(find.textContaining('removed at Campus A'), findsOneWidget);
  });

  testWidgets('adding needs a campus, posts the chosen role, and shows a server refusal verbatim', (tester) async {
    final server = _Server((o) {
      if (o.method == 'POST') {
        return _json(403, {'status': 403, 'message': 'Active staff assignment to this campus is required'});
      }
      return _json(200, []);
    });
    await tester.pumpWidget(_host(server));
    await tester.pumpAndSettle();
    final add = find.byKey(const Key('campus-role-add'));
    expect(tester.widget<AppButton>(add).onPressed, isNull, reason: 'no campus chosen yet');
    await tester.tap(find.byKey(const Key('campus-role-campus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Campus B').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    final post = server.requests.singleWhere((r) => r.method == 'POST');
    expect(post.path, '/api/users/u1/campus-grants');
    expect(post.data, {'campusId': 'cb', 'role': 'teacher'});
    expect(find.text('Active staff assignment to this campus is required'), findsOneWidget);
  });
}
