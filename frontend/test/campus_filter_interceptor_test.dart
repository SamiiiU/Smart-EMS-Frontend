import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';
import 'package:smartems/core/network/campus_filter_interceptor.dart';

class _Server implements HttpClientAdapter {
  _Server([this.gate]);
  final Completer<void>? gate;
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async {
    requests.add(o);
    await gate?.future;
    return ResponseBody.fromBytes(
      utf8.encode(jsonEncode({'content': []})),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dio(_Server s, String? Function() campus) =>
    Dio(BaseOptions(baseUrl: ApiConfig.baseUrl))
      ..httpClientAdapter = s
      ..interceptors.add(CampusFilterInterceptor(selectedCampus: campus));

void main() {
  test('list reads carry the selected campus', () async {
    final server = _Server();
    await _dio(server, () => 'A').get<dynamic>('/api/students');
    expect(server.requests.single.queryParameters['campusId'], 'A');
  });

  test(
    'All Campuses (no selection) sends no filter; other paths untouched',
    () async {
      final server = _Server();
      final dio = _dio(server, () => null);
      await dio.get<dynamic>('/api/students');
      await dio.get<dynamic>('/api/fee/plans');
      expect(
        server.requests.every(
          (r) => !r.queryParameters.containsKey('campusId'),
        ),
        isTrue,
      );
    },
  );

  test('a late response for the previous campus is rejected', () async {
    final gate = Completer<void>();
    final server = _Server(gate);
    var campus = 'A';
    final pending = _dio(server, () => campus).get<dynamic>('/api/sections');
    while (server.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    campus = 'B'; // switched while the request was in flight
    gate.complete();
    await expectLater(
      pending,
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
  });

  test('mutations are never rewritten by the filter', () async {
    final server = _Server();
    await _dio(
      server,
      () => 'A',
    ).post<dynamic>('/api/students', data: {'campusId': 'X'});
    expect(server.requests.single.queryParameters, isEmpty);
    expect((server.requests.single.data as Map)['campusId'], 'X');
  });
}
