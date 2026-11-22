import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/**
 * config/app_config.<flavor>.json의 app.name을 읽는다 (#9).
 *
 * 앱 표시 이름의 원본은 설정 JSON 한 곳이다. 여기에 이름을 따로 적지 않는다.
 * providers.fileContents로 읽어 JSON을 고치면 Gradle이 설정 단계를 다시 실행한다.
 */
fun appNameOf(flavor: String): String {
    val file = layout.projectDirectory.file("../../config/app_config.$flavor.json")
    val path = file.asFile.path
    val text = providers.fileContents(file).asText.orNull
        ?: throw GradleException("$path 파일이 없습니다")
    val root = JsonSlurper().parseText(text) as? Map<*, *>
    val name = (root?.get("app") as? Map<*, *>)?.get("name") as? String
    if (name.isNullOrBlank()) {
        throw GradleException("$path: app.name이 없거나 비어 있습니다")
    }
    // android:label 값이 @ 또는 ?로 시작하면 aapt가 리소스 참조로 해석한다.
    if (name.startsWith("@") || name.startsWith("?")) {
        throw GradleException("$path: app.name은 @ 또는 ?로 시작할 수 없습니다 (\"$name\")")
    }
    return name
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
    // 런처 이름(AndroidManifest.xml의 ${appName})은 flavor 설정 JSON의 app.name을 쓴다.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
        }
        create("stg") {
            dimension = "env"
            applicationIdSuffix = ".stg"
        }
        create("prod") {
            dimension = "env"
        }
    }
    productFlavors.configureEach {
        manifestPlaceholders["appName"] = appNameOf(name)
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
