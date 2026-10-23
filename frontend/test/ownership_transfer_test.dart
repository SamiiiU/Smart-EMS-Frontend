import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/theme/app_theme.dart';
import 'package:smartems/core/theme/typography.dart' show AppRole;
import 'package:smartems/features/admin/data/ownership_repository.dart';
import 'package:smartems/features/admin/presentation/ownership_transfer_screen.dart';

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

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.light(role: AppRole.admin),
  home: child,
);

void main() {
  testWidgets(
    'incoming owner: default is NO ACCESS, approval precedes accept',
    (tester) async {
      final server = _Server((o) {
        if (o.path == '/api/institution/ownership-transfer' &&
            o.method == 'GET') {
          return _json(200, {
            'id': 't1',
            'initiatedBy': 'old',
            'targetUserId': 'me',
          });
        }
        return _json(200, {'status': 'ok'});
      });
      final repo = OwnershipRepository(
        Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
          ..httpClientAdapter = server,
      );
      await tester.pumpWidget(
        _host(OwnershipTransferScreen(repository: repo, userId: 'me')),
      );
      await tester.pumpAndSettle();
      expect(find.text('No institution access (recommended)'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('Accept ownership'));
      await tester.pumpAndSettle();
      final posts = server.requests.where((r) => r.method == 'POST').toList();
      expect(posts[0].path, '/auth/mfa/approvals');
      expect((posts[0].data as Map)['targetId'], 't1');
      expect(posts[1].path, '/api/institution/ownership-transfer/t1/accept');
      expect((posts[1].data as Map)['formerOwnerAccess'], 'NONE');
    },
  );

  testWidgets(
    'incoming owner can explicitly keep the former owner as Institution Admin',
    (tester) async {
      final server = _Server(
        (o) => o.method == 'GET'
            ? _json(200, {
                'id': 't1',
                'initiatedBy': 'old',
                'targetUserId': 'me',
              })
            : _json(200, {}),
      );
      final repo = OwnershipRepository(
        Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
          ..httpClientAdapter = server,
      );
      await tester.pumpWidget(
        _host(OwnershipTransferScreen(repository: repo, userId: 'me')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('access-admin')));
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.text('Accept ownership'));
      await tester.pumpAndSettle();
      final accept = server.requests.firstWhere(
        (r) => r.path.endsWith('/accept'),
      );
      expect((accept.data as Map)['formerOwnerAccess'], 'INSTITUTION_ADMIN');
    },
  );

  testWidgets('a refused approval never sends the accept request', (
    tester,
  ) async {
    final server = _Server((o) {
      if (o.method == 'GET')
        return _json(200, {
          'id': 't1',
          'initiatedBy': 'old',
          'targetUserId': 'me',
        });
      if (o.path == '/auth/mfa/approvals')
        return _json(401, {'message': 'Invalid verification code'});
      return _json(200, {});
    });
    final repo = OwnershipRepository(
      Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = server,
    );
    await tester.pumpWidget(
      _host(OwnershipTransferScreen(repository: repo, userId: 'me')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    await tester.tap(find.text('Accept ownership'));
    await tester.pumpAndSettle();
    expect(find.text('Invalid verification code'), findsOneWidget);
    expect(server.requests.where((r) => r.path.endsWith('/accept')), isEmpty);
  });

  // F6: the irreversible accept form is fully described to assistive technology.
  testWidgets(
    'accept form: named choice group, required code, no request without a code',
    (tester) async {
      final handle = tester.ensureSemantics();
      final server = _Server(
        (o) => o.method == 'GET'
            ? _json(200, {
                'id': 't1',
                'initiatedBy': 'old',
                'targetUserId': 'me',
              })
            : _json(200, {}),
      );
      final repo = OwnershipRepository(
        Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
          ..httpClientAdapter = server,
      );
      await tester.pumpWidget(
        _host(OwnershipTransferScreen(repository: repo, userId: 'me')),
      );
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('What the current owner keeps'),
        findsOneWidget,
      );
      final code = tester.getSemantics(find.byType(EditableText));
      expect(code.label, 'Authenticator code');
      expect(code.hint, 'Required');
      await tester.tap(find.text('Accept ownership'));
      await tester.pumpAndSettle();
      expect(
        server.requests.where((r) => r.method == 'POST'),
        isEmpty,
        reason: 'no code means no approval and no accept',
      );
      handle.dispose();
    },
  );

  testWidgets(
    'initiator sees the waiting state with cancel, not the accept form',
    (tester) async {
      final server = _Server(
        (o) => _json(200, {
          'id': 't1',
          'initiatedBy': 'me',
          'targetUserId': 'new',
        }),
      );
      final repo = OwnershipRepository(
        Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
          ..httpClientAdapter = server,
      );
      await tester.pumpWidget(
        _host(OwnershipTransferScreen(repository: repo, userId: 'me')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cancel transfer'), findsOneWidget);
      expect(find.text('Accept ownership'), findsNothing);
    },
  );
}
