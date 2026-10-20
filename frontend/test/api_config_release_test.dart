import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/api_config.dart';

// DEF-27: a native release build must not fall back to localhost or plain http.
void main() {
  String resolve(String configured, {bool web = false, bool release = true}) =>
      ApiConfig.resolveBaseUrl(
        configured: configured,
        isWeb: web,
        isRelease: release,
        webOrigin: 'https://ems.example',
      );

  test('release native with no API_BASE_URL refuses to start', () {
    expect(() => resolve(''), throwsStateError);
  });

  test('release native with an http URL refuses to start', () {
    expect(() => resolve('http://api.example'), throwsStateError);
  });

  test('release native with an https URL uses it', () {
    expect(resolve('https://api.example'), 'https://api.example');
  });

  test('release web uses its own origin', () {
    expect(resolve('', web: true), 'https://ems.example');
  });

  test('debug native keeps the localhost fallback for development', () {
    expect(resolve('', release: false), 'http://localhost:8080');
  });
}
