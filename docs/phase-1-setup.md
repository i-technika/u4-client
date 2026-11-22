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
| Android 앱 이름 | U4 DEV | U4 STG | U4 |
| versionName | `pubspec.yaml`의 `version`과 같음 | 같음 | 같음 |
| 설정 파일 | `config/app_config.dev.json` | `config/app_config.stg.json` | `config/app_config.prod.json` |
| HTTP(cleartext) | 허용 | 차단 | 차단 |

- 앱 ID와 앱 이름은 임시값이다(0단계 문서 5장 "확인이 필요한 사항").
- Android는 `productFlavors`로 나눠, 세 flavor를 한 기기에 함께 설치할 수 있다.
- versionName은 flavor와 플랫폼에 관계없이 같다(예: `1.0.0`). Android flavor에 `versionNameSuffix`(`-dev` 등)를 두지 않는다.
  - `userAgentSuffix`의 `{version}`이 Android와 iOS에서 같아야 한다.
  - `extras.forceUpdate`는 semver로 비교하는데, `1.0.0-dev`는 pre-release라 `1.0.0`보다 낮게 취급되어 업데이트가 강제될 수 있다.
  - 환경은 applicationId 접미사와 앱 이름으로 구분한다.
- 실행 시 flavor는 `Flavor.current`가 정한다. Android는 `--flavor`, iOS는 `--dart-define=FLAVOR=`로 정하고, release 빌드에서 둘 다 없으면 시작하지 않는다.
- 세 설정 파일은 모두 asset으로 번들된다. 비밀 값이 없어서 그렇게 했지만, 설정에 민감한 값이 들어가게 되면 flavor별 asset으로 나눠야 한다.

### iOS flavor는 아직 없다

iOS는 bundle ID가 `com.itechnika.u4` 하나뿐이고, flavor는 `--dart-define`으로만 고른다. flavor별 bundle ID와 앱 이름을 주려면 Xcode에서 build configuration(`Debug-dev` 등)과 scheme을 만들어야 하는데, Windows에서는 Xcode 프로젝트를 안전하게 수정할 수 없어 macOS 환경에서 이어서 한다.

## 3. Android 설정

- **minSdk 28** (Android 9). 14단계 테스트 매트릭스(Android 9~16) 기준이다.
- **권한:** 인터넷, 네트워크 상태, 위치(정확·대략), 카메라, 마이크, 알림(Android 13+).
  - 카메라·GPS는 `uses-feature required="false"`로 두어 해당 하드웨어가 없는 기기도 설치할 수 있다.
  - 저장소·미디어 권한은 쓰지 않는다. `open_filex`가 추가하는 `READ_MEDIA_*`는 Play 사진·동영상 권한 정책 심사 대상이라 `tools:node="remove"`로 제거했다.
    - 사진·파일은 시스템 피커(Photo Picker)로 고르므로 권한이 필요 없다.
    - 그래서 설정의 `permissions.requestOnLaunch`에 `photos`가 있어도 Android에서는 요청하지 않는다(iOS에서만 요청). 선언이 없는 권한을 요청하면 곧바로 거부되고, `deniedGuide`가 켤 수 없는 권한 때문에 설정 앱으로 보내기 때문이다.
    - 권한 요청 코드는 `PermissionsConfig.requestOnLaunchOn(platform)`으로 플랫폼별 목록을 받는다. 플랫폼별 가능 여부는 `AppPermission.isRequestableOn`이 정한다 (#3).
  - CAMERA를 선언했으므로, 카메라 인텐트를 실행하기 전에 반드시 런타임 권한을 받아야 한다(8단계). 그렇지 않으면 크래시한다.
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
  - `LSApplicationQueriesSchemes`: `tel`, `sms`, `mailto`.
  - `NSAllowsLocalNetworking`: 로컬 테스트 페이지용. App Store 심사에서 허용되는 예외다.
- **macOS에서 처음 빌드할 때:** `flutter build ios`를 실행하면 `pod install`과 SwiftPM 해석이 이어서 진행된다. 이때 생기는 `ios/Podfile.lock`을 커밋한다.

## 5. 앱 코드

- `lib/config/app_config.dart`: 0단계 스키마를 그대로 옮긴 불변 모델이다.
  - 생략한 값은 스키마 기본값으로 채운다.
  - 모르는 enum 값이나 틀린 타입은 JSON 경로와 함께 시작 시 바로 실패한다.
  - prod 제약(https, 개발용 옵션 금지)을 한 번 더 검사한다.
- `lib/main.dart`: flavor 설정을 읽고 확인 화면을 띄운다. 2단계에서 `AppWebView`로 바꾼다.
  - 설정을 읽지 못하면(`AppConfigException`) `ConfigErrorApp`을 띄우고 예외를 `FlutterError.reportError`로 보고한다. 예외 내용은 debug에서만 보여 준다.
  - `AppConfig.load`는 asset 누락, JSON 형식 오류, 최상위 타입 오류도 파일 경로를 붙여 `AppConfigException`으로 던진다. 그 밖의 예외는 코드 버그로 보고 잡지 않는다.
- `test/`: 세 설정 파일 로딩, 기본값, 검증 실패 케이스, 플랫폼별 권한 목록, 확인 화면과 설정 실패 화면 위젯 테스트(29개).

## 6. 확인 결과

| 항목 | 결과 |
|---|---|
| `flutter analyze` | 이슈 없음 |
| `flutter test` | 29개 통과 |
| `flutter build apk --debug --flavor dev` / `stg` | 성공 |
| `flutter build apk --release --flavor prod` (R8) | 성공 |
| Android 에뮬레이터(API 36.1)에서 dev·prod 실행 | 설정 확인 화면 정상, dev·prod 함께 설치됨 |
| 병합된 prod 매니페스트 | 권한 8개(+ AndroidX 내부 권한), minSdk 28, targetSdk 36 |
| iOS 빌드·실행 | **미확인** (Windows 환경. macOS에서 확인 필요) |
| Android 실기기 실행 | **미확인** (에뮬레이터로만 확인) |

완료 기준 "양쪽 실기기에서 실행"은 iOS 빌드와 실기기 확인이 남아 있다.
