import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's light/dark preference, and where it is remembered.
///
/// Defaults to [ThemeMode.system] — following the device is right until the
/// person says otherwise, and both modes are token-complete and
/// contrast-tested, so neither is a fallback for the other.
///
/// Persisted with `shared_preferences`, the same store the session uses, so
/// the choice survives a relaunch. It is a DEVICE preference, not an account
/// one: there is no backend field for it, and inventing an endpoint is not
/// an option. It therefore stays put across sign-out, which is also what a
/// shared staff-room laptop wants.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController({ThemeMode initial = ThemeMode.system}) : super(initial);

  static const _key = 'ui.theme_mode';

  /// Reads the saved preference. A missing or unreadable value is not an
  /// error — it just means "follow the device".
  Future<void> restore() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      value = _fromWire(saved) ?? ThemeMode.system;
    } on Object {
      value = ThemeMode.system;
    }
  }

  /// Applies the choice immediately, then persists it. The UI never waits on
  /// the disk write — a theme tap that felt laggy would be worse than a
  /// preference that fails to save, which the next tap fixes anyway.
  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      await (await SharedPreferences.getInstance())
          .setString(_key, _toWire(mode));
    } on Object {
      // Ignored deliberately: the theme is already applied for this session.
    }
  }

  static String _toWire(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode? _fromWire(String? wire) => switch (wire) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
}
