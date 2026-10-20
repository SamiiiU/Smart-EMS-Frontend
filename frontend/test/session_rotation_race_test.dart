import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartems/core/network/token_store.dart';

class SlowStore extends InMemoryTokenStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> writeTokens({
    required String accessToken,
    required String? refreshToken,
  }) async {
    if (accessToken == 'rotated') {
      entered.complete();
      await release.future;
    }
    await super.writeTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }
}

void main() {
  test('late refresh cannot restore a logged out session', () async {
    final store = SerializedTokenStore(
      InMemoryTokenStore(accessToken: 'old', refreshToken: 'r'),
    );
    await store.clear();
    expect(await store.rotateIfCurrent('r', 'rotated', 'r2'), false);
    expect(await store.readAccessToken(), isNull);
  });
  test(
    'late refresh rejection cannot erase a newly logged in account',
    () async {
      final store = SerializedTokenStore(
        InMemoryTokenStore(accessToken: 'new-account', refreshToken: 'new-r'),
      );
      expect(await store.clearIfCurrent('old-r'), false);
      expect(
        await store.rotateIfCurrent('old-r', 'old-access', 'old-next'),
        false,
      );
      expect(await store.readAccessToken(), 'new-account');
    },
  );
  test(
    'logout queued during slow storage rotation wins after write settles',
    () async {
      final delegate = SlowStore()
        ..accessToken = 'old'
        ..refreshToken = 'r';
      final store = SerializedTokenStore(delegate);
      final rotation = store.rotateIfCurrent('r', 'rotated', 'r2');
      await delegate.entered.future;
      final logout = store.clear();
      delegate.release.complete();
      expect(await rotation, true);
      await logout;
      expect(await store.readAccessToken(), isNull);
      expect(await store.readRefreshToken(), isNull);
    },
  );
  test(
    'competing refresh responses cannot overwrite the winning pair',
    () async {
      final store = SerializedTokenStore(
        InMemoryTokenStore(accessToken: 'old', refreshToken: 'r'),
      );
      final results = await Future.wait([
        store.rotateIfCurrent('r', 'first', 'r1'),
        store.rotateIfCurrent('r', 'second', 'r2'),
      ]);
      expect(results, [true, false]);
      expect(await store.readAccessToken(), 'first');
    },
  );
}
