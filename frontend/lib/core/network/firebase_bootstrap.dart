import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Public Web registration; Android reads its own registration from google-services.json.
/// This is not an Admin SDK credential and does not enable push delivery.
class FirebaseBootstrap {
  FirebaseBootstrap._();

  static const webOptions = FirebaseOptions(
    apiKey: 'AIzaSyBYFh5HgsMavnDySwAByQ6Pp9HcehXZ6Rc',
    authDomain: 'babul-ems.firebaseapp.com',
    projectId: 'babul-ems',
    storageBucket: 'babul-ems.firebasestorage.app',
    messagingSenderId: '599728013512',
    appId: '1:599728013512:web:ea69d124ff63c33bcda5fd',
    measurementId: 'G-03Y22BG72W',
  );

  static Future<bool>? _initialization;

  /// Shared readiness future for future messaging consumers. Failure must not
  /// prevent offline UI startup. iOS and desktop await their own registrations.
  static Future<bool> initialize() =>
      _initialization ??= _initializeSupportedPlatform();

  static Future<bool> _initializeSupportedPlatform() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      if (kIsWeb) {
        await Firebase.initializeApp(options: webOptions);
      } else {
        await Firebase.initializeApp();
      }
      return true;
    } catch (error) {
      final code = error is FirebaseException
          ? error.code
          : error.runtimeType.toString();
      debugPrint(
        'Firebase initialization failed (code: $code); app remains available.',
      );
      return false;
    }
  }
}
