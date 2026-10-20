import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_web/flutter_secure_storage_web.dart';

/// Reading `instance` first forces any pending lazy initialisation of the
/// default, so the assignment below cannot be overwritten afterwards. Assigns
/// only when the web implementation is not already active (idempotent).
void ensureSecureStorageWebPlatform() {
  if (FlutterSecureStoragePlatform.instance is! FlutterSecureStorageWeb) {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageWeb();
  }
}
