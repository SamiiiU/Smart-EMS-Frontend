import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/token_gallery.dart';
import 'core/theme/typography.dart';

void main() {
  // Plus Jakarta Sans is bundled in assets/fonts/. Runtime fetching is OFF so
  // there is no network path for fonts at all: institutions are in
  // low-connectivity areas, and a cold offline first launch must still render
  // in the specified typeface rather than the platform fallback.
  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(const ProviderScope(child: SmartEmsApp()));
}

class SmartEmsApp extends StatefulWidget {
  const SmartEmsApp({super.key});

  @override
  State<SmartEmsApp> createState() => _SmartEmsAppState();
}

class _SmartEmsAppState extends State<SmartEmsApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleBrightness() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The token gallery is a design reference, not a role shell, so it needs
    // a role only to resolve a base body size. Teacher is used because it is
    // the middle of the four sizes — this is a gallery display choice, NOT a
    // product default. T5 sets the role per shell (D-24).
    const galleryRole = AppRole.teacher;

    return MaterialApp(
      title: 'Smart EMS',
      themeMode: _themeMode,
      theme: AppTheme.light(role: galleryRole),
      darkTheme: AppTheme.dark(role: galleryRole),
      home: TokenGalleryScreen(
        isDark: _themeMode == ThemeMode.dark,
        onToggleBrightness: _toggleBrightness,
      ),
    );
  }
}
