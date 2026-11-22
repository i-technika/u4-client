plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.itechnika.u4"
    // permission_handler_android 13.x가 37 이상을 요구한다. targetSdk는 Flutter 기본값 유지
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 임시 ID. 확정 전 (docs/phase-0-requirements.md 5장)
        applicationId = "com.itechnika.u4"
        // Android 9 (API 28) 이상 지원
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // config/app_config.<flavor>.json과 이름을 맞춘다. dev/stg는 prod와 함께 설치할 수 있게 ID를 나눈다.
    // versionNameSuffix는 일부러 두지 않는다. versionName을 flavor·플랫폼(iOS)과 같게 유지해야
    // userAgentSuffix의 {version}이 같고, extras.forceUpdate의 semver 비교에서
    // "1.0.0-dev"가 pre-release로 취급되어 업데이트가 강제되는 일이 없다. 환경은 ID와 앱 이름으로 구분한다.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            manifestPlaceholders["appName"] = "U4 DEV"
        }
        create("stg") {
            dimension = "env"
            applicationIdSuffix = ".stg"
            manifestPlaceholders["appName"] = "U4 STG"
        }
        create("prod") {
            dimension = "env"
            manifestPlaceholders["appName"] = "U4"
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

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
