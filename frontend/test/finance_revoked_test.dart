import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/core/widgets/states/error_state.dart';
import 'package:smartems/features/admin/data/admin_repository.dart';
import 'package:smartems/features/finance/data/finance_repository.dart';
import 'package:smartems/features/finance/presentation/finance_home_screen.dart';
import 'package:smartems/features/setup/data/setup_repository.dart';

/// Hard-QA BUG-QA-13 (remainder): finance revoked mid-session.
class _Server implements HttpClientAdapter {
  _Server({this.noCampusAtAll = false});
  final bool noCampusAtAll;
  final requested = <String>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<List<int>>? s, Future<void>? c) async {
    requested.add(o.path);
    final body = o.path.endsWith('/campuses/mine')
        ? noCampusAtAll
            ? {'campuses': <Object>[]}
            : {
            'campuses': [
              {'id': 'A', 'name': 'A', 'permissions': ['attendance.mark']},
            ],
          }
        : <String, Object>{};
    // (the noCampusAtAll branch above is the Pixel case: the revoked grant was the only one)
    return ResponseBody.fromBytes(utf8.encode(jsonEncode(body)), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('no fee campus left → permission state, and no finance data is fetched', (tester) async {
    final server = _Server();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = server;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: FinanceHomeScreen(
        finance: FinanceRepository(dio),
        setup: SetupRepository(dio),
        admin: AdminRepository(dio),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PermissionDeniedState), findsOneWidget);
    expect(find.textContaining('PKR'), findsNothing);
    expect(server.requested.where((p) => p.contains('/api/fee/')), isEmpty,
        reason: 'no financial endpoint is called once access is gone');
  });

  testWidgets('Pixel case: the revoked grant was the ONLY one (/mine is empty) → permission state with the reason', (tester) async {
    final server = _Server(noCampusAtAll: true);
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))..httpClientAdapter = server;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(role: AppRole.admin),
      home: FinanceHomeScreen(
        finance: FinanceRepository(dio),
        setup: SetupRepository(dio),
        admin: AdminRepository(dio),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PermissionDeniedState), findsOneWidget);
    expect(find.textContaining('No campus is available to your account for fees'), findsOneWidget);
    expect(server.requested.where((p) => p.contains('academic-years') || p.contains('/api/fee/')), isEmpty);
  });
}
