import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/shell/campus_context.dart';

class _Server implements HttpClientAdapter {
  _Server(this.body);
  Object body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async => ResponseBody.fromBytes(
    utf8.encode(jsonEncode(body)),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}

Map<String, Object> _mine(List<String> ids, {bool all = false}) => {
  'allCampuses': all,
  'campuses': [
    for (final id in ids)
      {
        'id': id,
        'name': 'Campus $id',
        'permissions': ['attendance.mark'],
      },
  ],
};

CampusContext _ctx(_Server s) => CampusContext(
  dio: Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))..httpClientAdapter = s,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'multiple campuses are never preselected; mutations need an explicit campus',
    () async {
      final ctx = _ctx(_Server(_mine(['A', 'B'])));
      await ctx.load(tenantId: 't', userId: 'u');
      expect(ctx.selectedId, isNull);
      expect(ctx.requireCampus, throwsStateError);
      await ctx.select('B');
      expect(ctx.requireCampus(), 'B');
    },
  );

  test(
    'All Campuses is only offered with institution-wide authority',
    () async {
      final scoped = _ctx(_Server(_mine(['A', 'B'])));
      await scoped.load(tenantId: 't', userId: 'u');
      expect(() => scoped.select(null), throwsStateError);
      expect(
        () => scoped.select('C'),
        throwsStateError,
        reason: 'ungranted campus',
      );

      final owner = _ctx(_Server(_mine(['A', 'B'], all: true)));
      await owner.load(tenantId: 't', userId: 'o');
      await owner.select(null);
      expect(owner.selectedId, isNull);
      expect(
        owner.requireCampus,
        throwsStateError,
        reason: 'All Campuses cannot be a mutation target',
      );
    },
  );

  test(
    'remembered per institution + user and revalidated on restore',
    () async {
      final server = _Server(_mine(['A', 'B']));
      final first = _ctx(server);
      await first.load(tenantId: 't', userId: 'u');
      await first.select('B');

      final restored = _ctx(server);
      await restored.load(tenantId: 't', userId: 'u');
      expect(restored.selectedId, 'B');

      final otherUser = _ctx(server);
      await otherUser.load(tenantId: 't', userId: 'someone-else');
      expect(
        otherUser.selectedId,
        isNull,
        reason: 'never inherits another account',
      );

      server.body = _mine(['A', 'C']); // B revoked
      final revoked = _ctx(server);
      await revoked.load(tenantId: 't', userId: 'u');
      expect(revoked.selectedId, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('campus:t:u'),
        isNull,
      );
    },
  );

  testWidgets('mutations never default to the first of several campuses', (
    tester,
  ) async {
    final ctx = _ctx(_Server(_mine(['A', 'B'])));
    await tester.runAsync(() => ctx.load(tenantId: 't', userId: 'u'));
    String? seen = 'unset';
    Widget probe(List<String> ids) => CampusScope(
      campus: ctx,
      child: Builder(
        builder: (context) {
          seen = explicitCampusFor(context, ids);
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(probe(['A', 'B']));
    expect(seen, isNull, reason: 'nothing chosen yet');
    await tester.runAsync(() => ctx.select('B'));
    await tester.pump();
    expect(seen, 'B');
    await tester.pumpWidget(probe(['A']));
    expect(
      seen,
      isNull,
      reason: 'selection outside the candidates is never used',
    );
  });

  testWidgets('without a campus context only a single campus is unambiguous', (
    tester,
  ) async {
    String? seen = 'unset';
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = explicitCampusFor(context, ['A', 'B']);
          return const SizedBox();
        },
      ),
    );
    expect(seen, isNull);
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          seen = explicitCampusFor(context, ['A']);
          return const SizedBox();
        },
      ),
    );
    expect(seen, 'A');
  });

  test('a single granted campus is the unambiguous selection', () async {
    final ctx = _ctx(_Server(_mine(['A'])));
    await ctx.load(tenantId: 't', userId: 'u');
    expect(ctx.requireCampus(), 'A');
    ctx.clear();
    expect(ctx.options, isEmpty);
    expect(ctx.selectedId, isNull);
  });
}
