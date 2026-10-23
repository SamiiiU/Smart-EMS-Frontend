import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/paged_get.dart';

/// Serves [total] rows in Spring-Page or hand-built envelopes.
class _PagedAdapter implements HttpClientAdapter {
  _PagedAdapter(this.total, {this.springPage = true});
  final int total;
  final bool springPage;
  final calls = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    calls.add(o.uri.toString());
    final page = int.parse('${o.queryParameters['page']}');
    final size = int.parse('${o.queryParameters['size']}');
    final start = page * size;
    final end = (start + size).clamp(0, total);
    final content = [for (var i = start; i < end; i++) {'id': '$i'}];
    final body = springPage
        ? {'content': content, 'number': page, 'size': size, 'totalElements': total, 'last': end >= total}
        : {'content': content, 'page': page, 'size': size, 'totalElements': total};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('walks every page of a Spring Page', () async {
    final a = _PagedAdapter(250);
    final dio = Dio()..httpClientAdapter = a;
    final rows = await dio.getAllPages('/x').timeout(const Duration(seconds: 5));
    expect(rows.length, 250);
    expect(a.calls.length, 3);
  });

  test('walks a hand-built envelope with no `last`', () async {
    final a = _PagedAdapter(150, springPage: false);
    final dio = Dio()..httpClientAdapter = a;
    final rows = await dio.getAllPages('/y').timeout(const Duration(seconds: 5));
    expect(rows.length, 150);
    expect(a.calls.length, 2);
  });

  test('concurrent identical calls share one request', () async {
    final a = _PagedAdapter(10);
    final dio = Dio()..httpClientAdapter = a;
    final r = await Future.wait([dio.getAllPages('/z'), dio.getAllPages('/z')])
        .timeout(const Duration(seconds: 5));
    expect(r[0].length, 10);
    expect(r[1].length, 10);
    expect(a.calls.length, 1);
  });
}
