import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartems/core/network/secure_token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'pair survives store reconstruction without plaintext preferences',
    () async {
      final first = SecureTokenStore();
      await first.writeTokens(accessToken: 'access', refreshToken: 'refresh');
      final restored = SecureTokenStore();
      expect(await restored.readAccessToken(), 'access');
      expect(await restored.readRefreshToken(), 'refresh');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.access_token'), isNull);
      expect(prefs.getString('auth.refresh_token'), isNull);
    },
  );
  test(
    'old plaintext credentials require fresh login without losing attendance',
    () async {
      SharedPreferences.setMockInitialValues({
        'auth.access_token': 'old',
        'auth.refresh_token': 'old-r',
      });
      FlutterSecureStorage.setMockInitialValues({
        'attendance.v2.owner': 'pending',
      });
      final store = SecureTokenStore();
      expect(await store.readAccessToken(), isNull);
      await store.writeTokens(accessToken: 'a', refreshToken: 'r');
      await store.clear();
      expect(await store.readRefreshToken(), isNull);
      expect(await store.storage.read(key: 'attendance.v2.owner'), 'pending');
    },
  );
  test('missing rotated token does not overwrite existing pair', () async {
    final store = SecureTokenStore();
    await store.writeTokens(accessToken: 'a', refreshToken: 'r');
    await expectLater(
      store.writeTokens(accessToken: 'new', refreshToken: null),
      throwsStateError,
    );
    expect(await store.readAccessToken(), 'a');
    expect(await store.readRefreshToken(), 'r');
  });
  test('corrupt vault fails without resetting stored data', () async {
    FlutterSecureStorage.setMockInitialValues({SecureTokenStore.key: 'broken'});
    final store = SecureTokenStore();
    await expectLater(store.readAccessToken(), throwsFormatException);
    expect(await store.storage.read(key: SecureTokenStore.key), 'broken');
  });
}
