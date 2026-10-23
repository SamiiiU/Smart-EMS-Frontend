import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/shell/role_destinations.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';

/// Found by the real-browser route crawl: finance staff (fee.view/fee.manage only)
/// saw a Dashboard and a Fees screen that both answered "You do not have permission".
class _Server implements HttpClientAdapter {
  _Server(this.respond);
  final ResponseBody Function(RequestOptions o) respond;
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    paths.add(o.path);
    return respond(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromBytes(utf8.encode(jsonEncode(body)), status,
    headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

void main() {
  test('fee-only roles get Fees but not the student-count Dashboard', () {
    final visible = RoleDestinations.visibleFor(RoleDestinations.admin, {'fee.view', 'fee.manage'}).map((d) => d.id).toList();
    expect(visible, contains('fees'));
    expect(visible, isNot(contains('dashboard')));
    expect(visible, isNot(contains('students')));
    final admin = RoleDestinations.visibleFor(RoleDestinations.admin, {'student.view', 'fee.view'}).map((d) => d.id);
    expect(admin, contains('dashboard'), reason: 'roles that can read the counts keep the dashboard');
  });

  test('campus list comes from /api/campuses/mine, which scoped roles may read', () async {
    final server = _Server((o) => o.path.endsWith('/mine')
        ? _json(200, {'allCampuses': false, 'campuses': [{'id': 'ca', 'name': 'Campus A', 'permissions': ['fee.view']}]})
        : _json(403, {'message': 'You do not have permission to access this resource'}));
    final repo = AdminRepository(Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = server);
    expect(await repo.loadCampusIds(), ['ca']);
    expect(server.paths, ['/api/campuses/mine'], reason: 'never the campus.manage-only list');
  });

  test('falls back to the plain list only when /mine does not exist', () async {
    final server = _Server((o) => o.path.endsWith('/mine')
        ? _json(404, {'message': 'No resource at this path'})
        : _json(200, {'content': [{'id': 'cb'}]}));
    final repo = AdminRepository(Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = server);
    expect(await repo.loadCampusIds(), ['cb']);
  });
}
