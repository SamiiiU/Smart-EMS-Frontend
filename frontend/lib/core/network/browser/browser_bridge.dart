// Browser-only capabilities behind a conditional import, so Android and VM
// tests never load `package:web`.
export 'browser_bridge_stub.dart'
    if (dart.library.js_interop) 'browser_bridge_web.dart';
