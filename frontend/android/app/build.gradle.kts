import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// DEF-27: release signing comes ONLY from the owner-held android/key.properties
// (gitignored, with the keystore outside the repo). There is no debug-key fallback.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    .all { !keyProperties.getProperty(it).isNullOrBlank() }

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

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
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
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release") else null
        }
    }
}

// DEF-27 guard: a release APK/AAB build stops unless it is signed with the release
// key AND compiled with an https:// API_BASE_URL. Flutter passes dart-defines to
// Gradle as base64 entries in the `dart-defines` property.
val releaseGuard = tasks.register("verifyReleaseConfig") {
    doLast {
        val defines = (project.findProperty("dart-defines") as String? ?: "")
            .split(",").filter { it.isNotBlank() }
            .map { String(Base64.getDecoder().decode(it)) }
        val apiUrl = defines.firstOrNull { it.startsWith("API_BASE_URL=") }?.removePrefix("API_BASE_URL=")
        if (apiUrl.isNullOrBlank() || !apiUrl.startsWith("https://")) {
            throw GradleException("Release build refused: --dart-define=API_BASE_URL=https://… is required (DEF-27).")
        }
        if (!hasReleaseKey) {
            throw GradleException("Release build refused: android/key.properties with the owner's release keystore is required (DEF-27).")
        }
    }
}
tasks.configureEach {
    if ((name.startsWith("assemble") || name.startsWith("bundle")) && name.endsWith("Release")) {
        dependsOn(releaseGuard)
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
