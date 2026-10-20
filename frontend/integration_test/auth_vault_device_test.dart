import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartems/core/network/secure_token_store.dart';
import 'package:smartems/core/network/token_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const nonce = String.fromEnvironment('ADR_VAULT_TEST_NONCE');
  const phase = String.fromEnvironment('ADR_VAULT_TEST_PHASE');
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'ems_adr_auth_test',
    ),
  );
  testWidgets(
    'real credential vault survives process restart and logout is scoped',
    (tester) async {
      expect(RegExp(r'^[a-f0-9]{12}$').hasMatch(nonce), true);
      expect(['write', 'read'].contains(phase), true);
      final store = SerializedTokenStore(SecureTokenStore(storage: storage));
      if (phase == 'write') {
        expect(await store.readAccessToken(), isNull);
        await storage.write(
          key: 'attendance.synthetic.$nonce',
          value: 'preserve',
        );
        await store.writeTokens(
          accessToken: 'adr-access-$nonce',
          refreshToken: 'adr-refresh-$nonce',
        );
      }
      expect(await store.readAccessToken(), 'adr-access-$nonce');
      expect(await store.readRefreshToken(), 'adr-refresh-$nonce');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('auth.access_token'), isNull);
      expect(prefs.getString('auth.refresh_token'), isNull);
      if (phase == 'read') {
        expect(
          await store.rotateIfCurrent(
            'adr-refresh-$nonce',
            'new-access',
            'new-refresh',
          ),
          true,
        );
        await store.clear();
        expect(await store.readRefreshToken(), isNull);
        expect(
          await storage.read(key: 'attendance.synthetic.$nonce'),
          'preserve',
        );
        await storage.delete(key: 'attendance.synthetic.$nonce');
      }
    },
  );
}
