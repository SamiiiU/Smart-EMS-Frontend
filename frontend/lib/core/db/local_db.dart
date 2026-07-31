// Conditional export barrel: picks the native sqlite3 connection on
// mobile/desktop and an in-memory stand-in on web, so lib/core/db/ can be
// imported from anywhere without callers needing to know the platform.
export 'local_db_native.dart' if (dart.library.js_interop) 'local_db_web.dart';
