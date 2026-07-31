import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Builds the light and dark [ThemeData] for Smart EMS, with
/// [SmartEmsTokens] attached as a [ThemeExtension] so
/// `Theme.of(context).extension<SmartEmsTokens>()` resolves per mode.
///
/// On [ColorScheme]: Material widgets read `ColorScheme`, so the tokens are
/// mapped onto it as an INTEROP SHIM only. `SmartEmsTokens` is the
/// authoritative source — components built in T2 and later must read the
/// extension directly, not `ColorScheme`. Slots with no corresponding token
/// are mapped to the nearest semantic token and marked below.
abstract final class AppTheme {
  /// [role] sets the base body size for this theme (D-24). It is required
  /// rather than defaulted: there is no global base body size in this system,
  /// so the caller must state which role shell the theme is for. T5 applies
  /// this per shell.
  static ThemeData light({required AppRole role}) {
    const t = SmartEmsTokens.light;
    return _build(
      tokens: t,
      role: role,
      scheme: ColorScheme(
        brightness: Brightness.light,
        primary: t.primaryAction,
        onPrimary: t.onPrimary,
        primaryContainer: t.primarySubtle,
        onPrimaryContainer: t.textPrimary,
        secondary: t.brandSurface,
        onSecondary: t.onBrand,
        secondaryContainer: t.brandSurfaceDeep,
        onSecondaryContainer: t.onBrandMuted,
        error: t.danger,
        // No token for "text on a solid danger fill"; danger is dark in
        // light mode, so onPrimary (white) is the correct pairing.
        onError: t.onPrimary,
        errorContainer: t.dangerBg,
        onErrorContainer: t.dangerTextOnBg,
        surface: t.surface,
        onSurface: t.textPrimary,
        onSurfaceVariant: t.textSecondary,
        surfaceContainerLowest: t.surface,
        surfaceContainerLow: t.surfaceSunken,
        surfaceContainer: t.surfaceSunken,
        outline: t.border,
        outlineVariant: t.borderStrong,
      ),
    );
  }

  static ThemeData dark({required AppRole role}) {
    const t = SmartEmsTokens.dark;
    return _build(
      tokens: t,
      role: role,
      scheme: ColorScheme(
        brightness: Brightness.dark,
        primary: t.primaryAction,
        onPrimary: t.onPrimary,
        primaryContainer: t.primarySubtle,
        onPrimaryContainer: t.textPrimary,
        secondary: t.brandSurface,
        onSecondary: t.onBrand,
        secondaryContainer: t.brandSurfaceDeep,
        onSecondaryContainer: t.onBrandMuted,
        error: t.danger,
        // No token for "text on a solid danger fill"; danger is LIGHT in
        // dark mode, so it needs a dark foreground — page is the darkest
        // neutral in the set.
        onError: t.page,
        errorContainer: t.dangerBg,
        onErrorContainer: t.dangerTextOnBg,
        surface: t.surface,
        onSurface: t.textPrimary,
        onSurfaceVariant: t.textSecondary,
        surfaceContainerLowest: t.surface,
        surfaceContainerLow: t.surfaceSunken,
        surfaceContainer: t.surfaceSunken,
        outline: t.border,
        outlineVariant: t.borderStrong,
      ),
    );
  }

  static ThemeData _build({
    required SmartEmsTokens tokens,
    required AppRole role,
    required ColorScheme scheme,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.page,
      canvasColor: tokens.surface,
      dividerColor: tokens.border,
      textTheme: AppTypography.textThemeFor(role).apply(
        bodyColor: tokens.textPrimary,
        displayColor: tokens.textPrimary,
      ),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }
}

/// Reads the Smart EMS tokens for the current mode.
///
/// Throws if the extension is missing rather than silently falling back to a
/// default — a missing extension means the widget is outside the app theme,
/// which is a wiring bug, not a condition to paper over.
extension SmartEmsThemeAccess on BuildContext {
  SmartEmsTokens get tokens {
    final t = Theme.of(this).extension<SmartEmsTokens>();
    assert(
      t != null,
      'SmartEmsTokens missing from Theme. Wrap the subtree in a MaterialApp '
      'built with AppTheme.light()/AppTheme.dark().',
    );
    return t ?? SmartEmsTokens.light;
  }
}
