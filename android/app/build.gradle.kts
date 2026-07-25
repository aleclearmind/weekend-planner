plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.claudietto.weekend_planner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.claudietto.weekend_planner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Keep plugin-provided native libraries aligned with Flutter's
        // --target-platform. Without this, Android can install an incomplete
        // non-arm64 ABI containing a plugin .so but no libflutter.so.
        ndk {
            val requested = (project.findProperty("target-platform") as String?)
                ?.split(",")
                ?.mapNotNull {
                    when (it.trim()) {
                        "android-arm" -> "armeabi-v7a"
                        "android-arm64" -> "arm64-v8a"
                        "android-x86" -> "x86"
                        "android-x64" -> "x86_64"
                        else -> null
                    }
                }
                .orEmpty()
            if (requested.isNotEmpty()) {
                abiFilters.clear()
                abiFilters.addAll(requested)
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
