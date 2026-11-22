# 1단계: 프로젝트 셋업

| 항목 | 내용 |
|---|---|
| 주요 작업 | 패키지 버전 고정, 번들 ID, minSdk/iOS 버전, Manifest·Info.plist 권한 문구, 기본 스킴용 Android `<queries>`, FileProvider |
| 완료 기준 | 빈 앱이 양쪽 실기기에서 실행 |
| 선행 단계 | 0단계 ([phase-0-requirements.md](phase-0-requirements.md)) |

## 1. 툴체인과 버전 고정

| 항목 | 버전 | 고정 위치 |
|---|---|---|
| Flutter | 3.50.0 (Dart 3.14.0) | `.fvmrc`(정확한 버전), `pubspec.yaml`의 `environment.flutter`(3.50.x만 허용) |
| Android Gradle Plugin | 9.3.1 | `android/settings.gradle.kts` (Flutter 템플릿 기본값) |
| Gradle | 9.5.0 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Kotlin | 2.4.20 | `android/settings.gradle.kts` |
| JDK | 17 이상 (Android Studio 내장 JBR로 확인) | — |

- 직접 의존성은 `pubspec.yaml`에 캐럿(`^`) 없이 정확한 버전으로 적고, 하위 의존성은 커밋한 `pubspec.lock`으로 고정한다.
- Flutter 3.50부터 Material 위젯은 `package:material_ui/material_ui.dart`에서 가져온다(템플릿 기본값). `package:flutter/material.dart` 대신 이것을 쓴다.

### 패키지

| 패키지 | 버전 | 용도 (단계) |
|---|---|---|
| `flutter_inappwebview` | **6.2.0-beta.3** | 웹뷰 (2) |
| `permission_handler` | 13.0.2 | 런타임 권한 (8, 9, 11, 13) |
| `url_launcher` | 6.3.3 | 기본 앱 스킴, 외부 링크 (2) |
| `geolocator` | 14.1.2 | geolocation 폴리필 (9) |
| `share_plus` | 13.3.1 | share 폴리필 (10) |
| `connectivity_plus` | 7.3.1 | 오프라인 감지 (12) |
| `app_links` | 7.2.2 | App/Universal Link (13) |
| `path_provider` | 2.1.6 | 다운로드 저장 위치 (10) |
| `open_filex` | 5.0.0 | 다운로드 파일 열기 (10) |
| `package_info_plus` | 10.2.2 | UA 접미사의 앱 버전 (2) |

1단계에서 넣지 않은 것:

- `firebase_messaging`: Firebase 프로젝트 파일(`google-services.json`, `GoogleService-Info.plist`)이 있어야 빌드된다. 13단계에서 추가한다.
- `flutter_native_splash`: 4단계에서 설정과 함께 추가한다.

### flutter_inappwebview를 beta로 고정한 이유

0단계 문서에서 "안정판 6.1.5 고정"을 전제로 했지만, 실제로 빌드해 보니 6.1.5는 현재 툴체인에서 빌드되지 않는다.

- 6.1.5의 Android 구현(`flutter_inappwebview_android` 1.1.3, 2024-10)은 `getDefaultProguardFile('proguard-android.txt')`를 쓴다. AGP 9는 이 파일을 지원하지 않아 Gradle 설정 단계에서 바로 실패한다.
- 6.2.0-beta.3(2026-02)은 `proguard-android-optimize.txt`로 바뀌어 AGP 9.3에서 빌드된다.
- AGP를 8.x로 내리는 방법도 있지만, Flutter 3.50 템플릿 기본값(AGP 9.3, Gradle 9.5)과 어긋나고 JDK·Gradle 조합 문제를 더 떠안게 되어 택하지 않았다.

대응:

- beta.3을 정확한 버전으로 고정하고, 안정판이 나오면 교체한다.
- 2단계에서 웹뷰 호출부를 `WebViewAdapter`로 감싸, 포크나 대체 패키지로 바꿀 때 영향을 줄인다.
- 통합 테스트(14단계)에서 beta 관련 회귀를 따로 확인한다.

### 그 밖의 버전 조정

- `connectivity_plus` 7.3.2는 `geolocator` 14.1.2와 Linux 구현의 `dbus` 버전이 충돌해 7.3.1로 고정했다.
- `permission_handler_android`가 compileSdk 37 이상을 요구해 `compileSdk = 37`로 올렸다. targetSdk는 Flutter 기본값(36)을 유지한다.

## 2. 앱 ID와 flavor

| | dev | stg | prod |
|---|---|---|---|
| Android applicationId | `com.itechnika.u4.dev` | `com.itechnika.u4.stg` | `com.itechnika.u4` |
| 설정 `app.name`, Android 앱 이름 | U4 DEV | U4 STG | U4 |
| iOS 앱 이름 | U4 | U4 | U4 |
| versionName | `pubspec.yaml`의 `version`과 같음 | 같음 | 같음 |
| 설정 파일 | `config/app_config.dev.json` | `config/app_config.stg.json` | `config/app_config.prod.json` |
| HTTP(cleartext) | 허용 | 차단 | 차단 |

- 앱 ID와 앱 이름은 임시값이다(0단계 문서 5장 "확인이 필요한 사항").
- Android는 `productFlavors`로 나눠, 세 flavor를 한 기기에 함께 설치할 수 있다.
- versionName은 flavor와 플랫폼에 관계없이 같다(예: `1.0.0`). Android flavor에 `versionNameSuffix`(`-dev` 등)를 두지 않는다.
  - `userAgentSuffix`의 `{version}`이 Android와 iOS에서 같아야 한다.
  - `extras.forceUpdate`는 semver로 비교하는데, `1.0.0-dev`는 pre-release라 `1.0.0`보다 낮게 취급되어 업데이트가 강제될 수 있다.
  - 환경은 applicationId 접미사와 앱 이름으로 구분한다.
- 앱 표시 이름(런처·홈 화면)의 기준은 설정 JSON의 `app.name`이다 (#9).
  - Android: `build.gradle.kts`가 빌드 시 `config/app_config.<flavor>.json`을 읽어 `manifestPlaceholders["appName"]`(매니페스트 `android:label`)에 넣는다. JSON만 고치면 된다.
    - `android:label`로 그대로 쓸 수 없는 이름은 빌드가 실패한다: 빈 이름, 앞 공백을 빼고 `@`·`?`로 시작(aapt가 리소스 참조로 해석), `\`(aapt 이스케이프), `${`(매니페스트 placeholder), 글자·숫자가 하나도 없는 이름.
    - 설정 단계에서 세 flavor 파일을 모두 읽으므로, 한 flavor 파일이 없거나 깨져도 모든 flavor 빌드가 실패한다. 오류에는 파일 경로가 붙는다.
  - iOS: Info.plist의 `CFBundleDisplayName`은 `$(APP_DISPLAY_NAME)`을 참조하고, 값은 `ios/Flutter/AppInfo.xcconfig`(Debug·Release xcconfig가 포함)에 손으로 적는다. 아래 "iOS flavor는 아직 없다" 때문에 flavor와 관계없이 prod 이름(U4)이 표시된다. **prod `app.name`을 바꾸면 `AppInfo.xcconfig`도 같이 고친다.**
  - `test/app_display_name_test.dart`가 연결이 끊기는 경우를 잡는다.
    - Android: 모든 매니페스트의 `android:label`(activity 포함)이 `${appName}` 하나뿐인지, Gradle의 `"appName"`이 `productFlavors.configureEach`의 `appNameOf(name)` 대입 한 곳에만 있는지, 번들 설정의 `app.name`이 위 규칙을 지키는지. `appNameOf`가 실제로 JSON 값을 돌려주는지는 빌드한 APK로 확인한다(`aapt2 dump badging`의 `application-label`). CI 자동 비교는 #39에서 추가한다.
    - iOS: `AppInfo.xcconfig` 값이 prod `app.name`과 같은지, Debug·Release xcconfig, Xcode 프로젝트, 지역화 `InfoPlist.strings`가 이름을 덮어쓰지 않는지.
  - Gradle은 JSON을 UTF-8로 읽는다. JVM 기본 문자셋이 UTF-8이 아니어도 한글 이름이 깨지지 않는다.
- 실행 시 flavor는 `Flavor.current`가 정한다. Android는 `--flavor`, iOS는 `--dart-define=FLAVOR=`로 정하고, release 빌드에서 둘 다 없으면 시작하지 않는다.
- 세 설정 파일은 모두 asset으로 번들된다. 비밀 값이 없어서 그렇게 했지만, 설정에 민감한 값이 들어가게 되면 flavor별 asset으로 나눠야 한다.

### iOS flavor는 아직 없다

iOS는 bundle ID가 `com.itechnika.u4` 하나뿐이고, flavor는 `--dart-define`으로만 고른다. flavor별 bundle ID와 앱 이름을 주려면 Xcode에서 build configuration(`Debug-dev` 등)과 scheme을 만들어야 하는데, Windows에서는 Xcode 프로젝트를 안전하게 수정할 수 없어 macOS 환경에서 이어서 한다.

flavor별 build configuration을 만들 때 각 xcconfig에서 `APP_DISPLAY_NAME`을 그 flavor의 `app.name`으로 덮어쓴다. 그때 `test/app_display_name_test.dart`의 "덮어쓰지 않는다" 검사를 flavor별 xcconfig 값이 그 flavor의 `app.name`과 같은지 보는 검사로 바꾼다. 이 작업은 #38에서 한다.

## 3. Android 설정

- **minSdk 28** (Android 9). 14단계 테스트 매트릭스(Android 9~16) 기준이다.
- **권한:** 인터넷, 네트워크 상태, 위치(정확·대략), 카메라, 마이크, 알림(Android 13+).
  - 카메라·GPS는 `uses-feature required="false"`로 두어 해당 하드웨어가 없는 기기도 설치할 수 있다.
  - 저장소·미디어 권한은 쓰지 않는다. `open_filex`가 추가하는 `READ_MEDIA_*`는 Play 사진·동영상 권한 정책 심사 대상이라 `tools:node="remove"`로 제거했다.
    - 웹뷰 파일 업로드는 시스템 파일 선택기(`ACTION_GET_CONTENT`)로 고르고 임시 URI 권한을 받으므로 저장소 권한이 필요 없다(API 28~36). 촬영 선택지는 FileProvider URI를 쓰며, CAMERA 권한이 없으면 크래시하지 않고 선택지에서 빠진다.
    - `open_filex`는 앱 영역(`dataDir`, `getExternalFilesDir`) 밖의 파일을 열 때 미디어·저장소 권한을 직접 요청한다. 이 권한은 제거했으므로 앱 영역 경로만 넘긴다(10단계 다운로드).
    - 매니페스트 테스트(`test/app_config_test.dart`)가 main의 제거 선언(`tools:selector` 없이)과, 다른 source set이나 `uses-permission-sdk-23`으로 다시 선언하지 않는지를 검사한다.
  - **`photos` 권한은 Android에서 요청하지 않는다 (#3).** 설정의 `permissions.requestOnLaunch`에 `photos`가 있어도 건너뛴다.
    - permission_handler는 매니페스트에 없는 권한을 다이얼로그 없이 항상 `denied`로 돌려준다(영구 거부가 아님). 요청하면 기능이 늘 실패하고, 영구 거부가 아니라 설정 앱 안내로도 이어지지 않는다.
    - Android 12(API 32) 이하는 permission_handler가 photos를 지원하지 않아 매니페스트와 상관없이 `denied`다. 이 버전에서 필요해지면 `READ_EXTERNAL_STORAGE`(maxSdkVersion 32) 제거를 풀고 `storage`로 따로 매핑해야 한다.
  - CAMERA를 선언했으므로, 앱이 카메라 인텐트를 직접 실행할 때는 먼저 런타임 권한을 받아야 한다(8단계). 그렇지 않으면 `SecurityException`으로 실패한다.
- **`<queries>`:** `tel`(DIAL), `sms`·`mailto`(SENDTO), `geo`(VIEW), `https`(VIEW), Custom Tabs 서비스, 이미지·동영상 촬영 인텐트.
- **FileProvider:** `U4FileProvider`(authority `${applicationId}.fileprovider`)를 쓴다. 플러그인들도 `androidx.core.content.FileProvider`를 등록하므로, 매니페스트 병합 충돌을 피하려고 하위 클래스로 만들었다. 경로는 `res/xml/file_paths.xml`의 `cache/camera/`, `files/downloads/`다.
- **네트워크 보안:**
  - 기본(stg/prod)은 HTTPS만 허용하고, debug 빌드에서만 사용자 인증서를 신뢰한다.
  - dev는 `src/dev/res/xml/network_security_config.xml`이 기본 설정을 덮어써 HTTP와 사용자 인증서를 허용한다.
- 키보드 대응(`adjustResize`)은 템플릿 기본값을 유지한다.
- release 서명은 아직 debug 키다. 15단계(출시 준비)에서 업로드 키를 설정한다.

## 4. iOS 설정

- **최소 버전 iOS 16** (`IPHONEOS_DEPLOYMENT_TARGET`, Podfile `platform`).
- **플러그인 연결:** 기본은 Swift Package Manager다. `flutter_inappwebview_ios`처럼 SwiftPM을 지원하지 않는 플러그인만 CocoaPods로 설치되므로 `ios/Podfile`을 미리 두었다.
- **`permission_handler` 권한 매크로:**
  - SwiftPM으로 설치되면 Info.plist의 `NS*UsageDescription` 키를 보고 자동으로 켠다.
  - CocoaPods로 설치될 때를 대비해 Podfile `post_install`에도 같은 목록(위치, 카메라, 마이크, 사진, 알림)을 넣었다. 두 목록은 같게 유지한다.
- **Info.plist:**
  - 권한 문구: 카메라, 마이크, 위치(사용 중), 사진 보관함 읽기·추가.
- **`photos` 권한:** iOS에서는 설정대로 요청한다. 다만 웹 파일 업로드에는 사진 보관함 권한이 필요 없다(시스템 피커). 보관함을 네이티브로 직접 읽는 기능이 있을 때만 `photos`를 쓴다. iOS 14+의 `limited` 처리는 권한 요청을 구현하는 단계에서 정한다.
  - `LSApplicationQueriesSchemes`: `tel`, `sms`, `mailto`.
  - `NSAllowsLocalNetworking`: 로컬 테스트 페이지용. App Store 심사에서 허용되는 예외다.
- **macOS에서 처음 빌드할 때:** `flutter build ios`를 실행하면 `pod install`과 SwiftPM 해석이 이어서 진행된다. 이때 생기는 `ios/Podfile.lock`을 커밋한다.

## 5. 앱 코드

- `lib/config/app_config.dart`: 0단계 스키마를 그대로 옮긴 불변 모델이다.
  - 생략한 값은 스키마 기본값으로 채운다.
  - 모르는 enum 값이나 틀린 타입은 JSON 경로와 함께 시작 시 바로 실패한다.
  - 스키마에 없는 키(오타 포함)는 값을 읽기 전에 경로를 모두 모아 실패한다(#4). 오타 난 키가 조용히 무시되어 기본값이 쓰이는 것을 막고, 필수 키 오타(`startURL`)도 "필요합니다" 대신 오타 위치로 알린다.
    - 아는 키 목록(`AppConfig.knownKeys`)은 최소 설정으로 모델을 한 번 만들며 읽은 키를 기록해 얻는다. 그래서 모델은 스키마의 모든 키를 조건 없이 읽어야 한다.
    - 이 목록이 스키마의 object별 속성과 정확히 같은지, `properties`로 이어지는 모든 object가 `additionalProperties: false`인지는 테스트가 확인한다. 스키마와 모델 중 한쪽만 고치면 테스트가 실패한다.
    - 배열 원소 object나 `allOf`·`anyOf`·`oneOf`로 키를 정의하는 스키마는 로더가 지원하지 않으며, 테스트가 막는다.
    - 최소 설정이 모델의 필수 키나 읽기 단계 검사와 어긋나면 `StateError`(코드 버그)로 실패한다. 필수 키를 늘리거나 읽기 단계에 범위 검사를 넣을 때(#5) 함께 고친다.
  - 아는 키에 `null`을 직접 적으면 기본값을 쓰지 않고 실패한다(생략은 허용).
  - 로더가 다시 검사하는 것: 모르는 키, 필수 키, 타입, enum 값, 색상 형식, URL에 scheme·host가 있는지, `allowedHosts`가 비었는지, 강제 업데이트의 `checkUrl`, prod 제약.
  - 로더가 검사하지 않는 것(범위, `hostPattern`, URL scheme 종류, `uniqueItems` 등)은 CI가 막는다. `tool/validate_config.sh`가 `check-jsonschema`로 번들 설정 파일을 검증한다. `format: uri` 검사 패키지(`rfc3986-validator`)가 빠지면 잘못된 URI도 통과하므로, 스크립트는 fixture가 uri 형식 오류 하나로만 실패하는지 확인한다. 버전은 `tool/requirements-ci.txt`에 고정했다. 런타임 범위 검사는 #5에서 다룬다.
  - prod 제약(https, 개발용 옵션 금지)을 한 번 더 검사한다.
  - **권한 (#3):** 설정 파일은 플랫폼 공통이라 플랫폼마다 건너뛸 권한이 있다.
    - 권한 요청 코드(8·9·11·13단계)는 시작 시 목록을 `PermissionsConfig.requestOnLaunchOn(defaultTargetPlatform)`으로만 받는다. 설정 원본 목록은 공개하지 않는다.
    - 기능을 쓸 때 요청하는 경로도 `AppPermission.isRequestableOn(defaultTargetPlatform)`을 먼저 확인한다.
    - `isRequestableOn`은 매니페스트·플러그인 제약 때문에 그 플랫폼에서 요청 자체를 건너뛸지만 정한다(플랫폼 단위). API 레벨에 따른 실제 상태는 permission_handler가 돌려준다. 지금은 Android의 `photos`만 `false`다.
    - `deniedGuide`는 `isPermanentlyDenied`일 때만 설정 앱 이동을 안내한다.
- `lib/main.dart`: flavor 설정을 읽고 확인 화면을 띄운다. 2단계에서 `AppWebView`로 바꾼다.
  - 설정을 읽지 못하면(`AppConfigException`) `ConfigErrorApp`을 띄우고 예외를 `FlutterError.reportError`로 보고한다. 예외 내용은 debug에서만 보여 준다.
  - `AppConfig.load`는 asset 누락, JSON 형식 오류, 최상위 타입 오류를 포함해 모든 설정 오류에 파일 경로를 붙여 `AppConfigException`으로 던진다. 그 밖의 예외는 코드 버그로 보고 잡지 않는다.
- `test/`: 세 설정 파일 로딩, 기본값, 검증 실패 케이스, 플랫폼별 권한 목록, 모르는 키와 스키마·모델 일치(#4), 확인 화면과 설정 실패 화면 위젯 테스트(45개).

## 6. 확인 결과

| 항목 | 결과 |
|---|---|
| `flutter analyze` | 이슈 없음 |
| `flutter test` | 45개 통과 (#4 반영 후) |
| `flutter build apk --debug --flavor dev` / `stg` | 성공 |
| `flutter build apk --release --flavor prod` (R8) | 성공 |
| Android 에뮬레이터(API 36.1)에서 dev·prod 실행 | 설정 확인 화면 정상, dev·prod 함께 설치됨 |
| 병합된 prod 매니페스트 | 권한 8개(+ AndroidX 내부 권한), minSdk 28, targetSdk 36 |
| iOS 빌드·실행 | **미확인** (Windows 환경. macOS에서 확인 필요) |
| Android 실기기 실행 | **미확인** (에뮬레이터로만 확인) |

완료 기준 "양쪽 실기기에서 실행"은 iOS 빌드와 실기기 확인이 남아 있다.
