/// Ensures `flutter_secure_storage` uses its WEB implementation on web
/// (P0 WEB-INTENT-1). No-op on every other platform.
///
/// Root cause: in the fully optimised dart2js release build (-O4) the
/// platform interface's lazily-initialised default
/// (`_instance = MethodChannelFlutterSecureStorage()`) could win over the web
/// plugin registrant's earlier `instance = FlutterSecureStorageWeb()`, so every
/// read went to the native method channel
/// `plugins.it_nomads.com/flutter_secure_storage`, which does not exist on web
/// (MissingPluginException). Record Payment then reported its recovery storage
/// as unavailable and refused to submit.
///
/// The fix re-asserts exactly what the plugin's own `registerWith` does — same
/// plugin, same options, same keys — so the storage format and existing
/// records are unchanged.
library;

export 'secure_storage_platform_stub.dart'
    if (dart.library.js_interop) 'secure_storage_platform_web.dart';
