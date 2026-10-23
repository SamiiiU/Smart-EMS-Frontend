plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.babultech.smartems"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.babultech.smartems"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        // Physical-device rehearsal: every NON-release build is a separate app
        // (com.babultech.smartems.staging, "Smart EMS Staging") so it can never
        // overwrite an installed production/personal Smart EMS app.
        configureEach {
            if (name != "release") {
                applicationIdSuffix = ".staging"
                manifestPlaceholders["appLabel"] = "Smart EMS Staging"
            } else {
                manifestPlaceholders["appLabel"] = "smartems"
            }
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// The Firebase project only registers the production package. Non-release (staging)
// variants skip google-services processing: no Firebase config, so push stays OFF for
// the staging app (Firebase.initializeApp fails closed and is caught at startup).
tasks.configureEach {
    if (name.startsWith("process") && name.endsWith("GoogleServices") && !name.contains("Release")) {
        enabled = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
