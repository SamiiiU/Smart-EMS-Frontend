import 'package:integration_test/integration_test_driver.dart';

/// Driver for `flutter drive`, which is how integration tests run on the WEB
/// target — the one this product ships to.
///
/// ```
/// chromedriver --port=4444
/// flutter drive \
///   --driver=test_driver/integration_test.dart \
///   --target=integration_test/app_smoke_test.dart \
///   -d chrome --web-port=3000 --browser-name=chrome
/// ```
///
/// Port 3000 is not a preference: the backend's CORS allowlist is
/// origin-exact, so any other port is blocked by the browser.
///
/// On Android the driver is not needed — with a device or emulator attached,
/// `flutter test integration_test/app_smoke_test.dart` is enough.
Future<void> main() => integrationDriver();
