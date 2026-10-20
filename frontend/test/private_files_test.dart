import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/private_files_repository.dart';
import 'package:smartems/core/network/auth_interceptor.dart';
import 'package:smartems/core/network/token_store.dart';

const id = '00000000-0000-0000-0000-000000000001';

class Adapter implements HttpClientAdapter {
  Adapter(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  final bodies = <String>[];
  final paths = <String>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    paths.add(options.path);
    if (stream != null) {
      final bytes = <int>[];
      await for (final part in stream) {
        bytes.addAll(part);
      }
      bodies.add(utf8.decode(bytes));
    }
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

class Refresher implements TokenRefresher {
  Refresher(this.store);
  final TokenStore store;
  int calls = 0;
  @override
  Future<String?> refresh(String refreshToken) async {
    calls++;
    await store.writeTokens(accessToken: 'fresh', refreshToken: 'rotated');
    return 'fresh';
  }
}

void main() {
  test(
    'authenticated binary request uses only fixed application route',
    () async {
      final store = InMemoryTokenStore();
      await store.writeTokens(accessToken: 'valid', refreshToken: 'refresh');
      final adapter = Adapter((options) {
        expect(options.path, '/api/files/$id/content');
        expect(options.headers['Authorization'], 'Bearer valid');
        expect(options.responseType, ResponseType.bytes);
        return ResponseBody.fromBytes([0, 1, 255], 200);
      });
      final dio = Dio(BaseOptions(baseUrl: 'https://application.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(
        AuthInterceptor(
          tokenStore: store,
          refresher: Refresher(store),
          retryDio: Dio(),
        ),
      );
      expect(await PrivateFilesRepository(dio).download(id), [0, 1, 255]);
    },
  );
  test(
    'multipart refresh replay preserves bytes and stable idempotency key',
    () async {
      final store = InMemoryTokenStore();
      await store.writeTokens(accessToken: 'stale', refreshToken: 'refresh');
      final refresher = Refresher(store);
      var attempts = 0;
      final adapter = Adapter((options) {
        attempts++;
        expect(options.headers['Idempotency-Key'], id);
        expect(
          options.headers['Authorization'],
          attempts == 1 ? 'Bearer stale' : 'Bearer fresh',
        );
        return ResponseBody.fromString(
          jsonEncode(
            attempts == 1
                ? {'message': 'expired'}
                : {'id': id, 'status': 'ready'},
          ),
          attempts == 1 ? 401 : 201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
      final retry = Dio(BaseOptions(baseUrl: 'https://application.test'))
        ..httpClientAdapter = adapter;
      final dio = Dio(BaseOptions(baseUrl: 'https://application.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(
        AuthInterceptor(
          tokenStore: store,
          refresher: refresher,
          retryDio: retry,
        ),
      );
      final result = await PrivateFilesRepository(dio).upload(
        bytes: Uint8List.fromList(utf8.encode('synthetic upload')),
        filename: 'notes.txt',
        scope: 'PRIVATE',
        resourceId: id,
        requestKey: id,
      );
      expect(result['id'], id);
      expect(refresher.calls, 1);
      expect(adapter.bodies.length, 2);
      for (final body in adapter.bodies) {
        expect(body, contains('synthetic upload'));
        expect(body, contains('notes.txt'));
      }
    },
  );
  test(
    'provider URLs and path injection are rejected before network requests',
    () async {
      final adapter = Adapter((options) => throw StateError('must not fetch'));
      final dio = Dio(BaseOptions(baseUrl: 'https://application.test'))
        ..httpClientAdapter = adapter;
      for (final value in ['https://cloudinary.test/secret', '../other-file']) {
        await expectLater(
          PrivateFilesRepository(dio).download(value),
          throwsArgumentError,
        );
      }
      expect(adapter.paths, isEmpty);
    },
  );
}
