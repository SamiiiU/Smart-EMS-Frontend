/// Non-browser stand-in: there is no cookie jar or cross-tab lock to use.
String? readCookie(String name) => null;

Future<T> withCrossTabLock<T>(String name, Future<T> Function() action) => action();
