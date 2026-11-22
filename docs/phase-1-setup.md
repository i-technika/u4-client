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
| iOS bundle ID | `com.itechnika.u4.dev` | `com.itechnika.u4.stg` | `com.itechnika.u4` |
| 설정 `app.name`, Android·iOS 앱 이름 | U4 DEV | U4 STG | U4 |
| iOS scheme / build configuration | `dev` / `Debug-dev`·`Release-dev`·`Profile-dev` | `stg` / `*-stg` | `prod` / `*-prod` |
| versionName | `pubspec.yaml`의 `version`과 같음 | 같음 | 같음 |
| 설정 파일 | `config/app_config.dev.json` | `config/app_config.stg.json` | `config/app_config.prod.json` |
| Android HTTP(cleartext) | 허용 | 차단 | 차단 |
| iOS HTTP(ATS) | 로컬 네트워크만 허용 | 같음 | 같음 |

- 앱 ID와 앱 이름은 임시값이다(0단계 문서 5장 "확인이 필요한 사항").
- Android는 `productFlavors`, iOS는 scheme과 build configuration으로 나눠, 세 flavor를 한 기기에 함께 설치할 수 있다.
- versionName은 flavor와 플랫폼에 관계없이 같다(예: `1.0.0`). Android flavor에 `versionNameSuffix`(`-dev` 등)를 두지 않는다.
  - `userAgentSuffix`의 `{version}`이 Android와 iOS에서 같아야 한다.
  - `extras.forceUpdate`는 semver로 비교하는데, `1.0.0-dev`는 pre-release라 `1.0.0`보다 낮게 취급되어 업데이트가 강제될 수 있다.
  - 환경은 applicationId 접미사와 앱 이름으로 구분한다.
- 앱 표시 이름(런처·홈 화면)의 기준은 설정 JSON의 `app.name`이다 (#9).
  - Android: `build.gradle.kts`가 빌드 시 `config/app_config.<flavor>.json`을 읽어 `manifestPlaceholders["appName"]`(매니페스트 `android:label`)에 넣는다. JSON만 고치면 된다.
    - `android:label`로 그대로 쓸 수 없는 이름은 빌드가 실패한다: 빈 이름, 앞 공백을 빼고 `@`·`?`로 시작(aapt가 리소스 참조로 해석), `\`(aapt 이스케이프), `${`(매니페스트 placeholder), 글자·숫자가 하나도 없는 이름.
    - 설정 단계에서 세 flavor 파일을 모두 읽으므로, 한 flavor 파일이 없거나 깨져도 모든 flavor 빌드가 실패한다. 오류에는 파일 경로가 붙는다.
  - iOS: Info.plist의 `CFBundleDisplayName`은 `$(APP_DISPLAY_NAME)`을 참조하고, 값은 `ios/Flutter/AppInfo-<flavor>.xcconfig`에 손으로 적는다(아래 "iOS flavor"). Xcode는 빌드 시 JSON을 읽지 않으므로 **`app.name`을 바꾸면 그 flavor의 `AppInfo-<flavor>.xcconfig`도 같이 고친다.**
  - `test/app_display_name_test.dart`가 연결이 끊기는 경우를 잡는다.
    - Android: 모든 매니페스트의 `android:label`(activity 포함)이 `${appName}` 하나뿐인지, Gradle의 `"appName"`이 `productFlavors.configureEach`의 `appNameOf(name)` 대입 한 곳에만 있는지, 번들 설정의 `app.name`이 위 규칙을 지키는지. `appNameOf`가 실제로 JSON 값을 돌려주는지는 이 테스트로 보지 않는다.
    - iOS: `AppInfo-<flavor>.xcconfig`의 이름이 그 flavor의 `app.name`과, bundle ID가 Android applicationId와 같은지, build configuration·scheme이 다른 flavor의 xcconfig를 쓰지 않는지, configuration xcconfig·Xcode 프로젝트·지역화 `InfoPlist.strings`가 값을 덮어쓰지 않는지.
  - CI가 빌드한 APK의 런처 이름을 JSON과 비교한다 (#39). `tool/check_android_app_label.sh`가 `aapt2 dump badging`에서 `application-label`, 로캘별 `application-label-<로캘>`(리소스에 있는 로캘마다 나온다), `launchable-activity`·`leanback-launchable-activity`의 `label`을 읽어 APK 파일 이름(`app-<flavor>-<buildType>.apk`)의 flavor JSON `app.name`과 비교한다. 값이 하나라도 다르면 기대값·실제값을 출력하고 실패한다. 기본 라벨·`launchable-activity` 줄이 없거나, 라벨 줄인데 값을 읽지 못한 줄(출력 형식 변화)이 있으면 관련 덤프 줄을 출력하고 실패한다.
    - activity 라벨이 비어 있으면 앱 라벨을 물려받으므로 통과로 본다. 속성이 없는 것과 `android:label=""`은 badging으로 구분되지 않는데, 후자는 위 정적 테스트가 막는다. `application: label=` 줄은 `application-label`과 같은 값이라 보지 않는다.
    - Sub-issue Linux CI는 dev·prod debug APK를, Milestone Full CI는 dev·stg·prod release APK를 검사한다. stg만 달라지는 회귀는 Milestone Full CI에서 드러난다.
    - aapt2는 라벨을 출력할 때 `\`·`"`·줄바꿈만 이스케이프한다(탭 등은 그대로). 기대값도 같은 표기로 바꿔 문자열로 비교하고, 실패 메시지의 기대·실제 값도 이 표기다. aapt2가 매니페스트 문자열을 처리하며 공백 등을 바꾸면 런처 이름이 JSON과 실제로 다른 것이므로 실패로 본다.
    - 판정 로직은 매번 내장 fixture로 먼저 확인한다. 정상 덤프(이름에 `'`·`"`·탭·CR·`label='`·`icon='` 포함, CRLF 출력, `banner=`가 붙은 TV activity 줄)는 통과하고, 라벨 하나가 다르거나(로캘·TV activity 포함, 숫자 표기·뒤 공백만 다른 경우 포함) 라벨 줄이 빠지거나 값을 읽을 수 없는 덤프는 실패해야 한다. JSON → aapt2 표기 변환과 파일 이름 → flavor 변환도 같이 확인한다.
      - 탭·CR 등이 든 이름은 파서가 값을 자르지 않는지 보려는 것이다. 그런 이름이 실제 빌드에서 그대로 남는다는 뜻은 아니다(매니페스트에 리터럴 탭을 쓰면 aapt2가 공백으로 바꾼다). 바뀌면 불일치로 실패한다.
  - Gradle은 JSON을 UTF-8로 읽는다. JVM 기본 문자셋이 UTF-8이 아니어도 한글 이름이 깨지지 않는다.
- 실행 시 flavor는 `Flavor.current`가 정한다. Android·iOS 모두 `--flavor` 값을 Flutter가 넘겨 주는 `appFlavor`로 읽고, release 빌드에서 없으면 시작하지 않는다. 예전 iOS용 `--dart-define=FLAVOR=`는 #38에서 없앴다(bundle ID와 다른 flavor 설정을 읽는 빌드를 막기 위해).
  - 값이 `--flavor`와 같으면 무시한다. 다르거나 `--flavor` 없이 넘기면 빌드는 되지만 앱이 설정 오류 화면(`ConfigErrorApp`)으로 시작한다. 빌드·배포 스크립트에 남아 있으면 지운다.
  - 판정 규칙은 `Flavor.resolve`에 있고 `test/flavor_test.dart`가 확인한다.
- 세 설정 파일은 모두 asset으로 번들된다. 비밀 값이 없어서 그렇게 했지만, 설정에 민감한 값이 들어가게 되면 flavor별 asset으로 나눠야 한다.

### iOS flavor (#38)

Flutter의 iOS flavor 규칙(scheme 이름 = flavor, build configuration 이름 = `<모드>-<flavor>`)을 따른다. macOS에서 만들었다.

- scheme `dev`·`stg`·`prod`만 있다. flavor 없는 `Runner` scheme은 지웠으므로 `--flavor` 없이 iOS를 빌드할 수 없다(Android와 같다).
- build configuration은 `Debug`·`Release`·`Profile` × flavor 9개다. 프로젝트·Runner·RunnerTests 모두 같은 9개를 가진다.
- xcconfig 구성 (`ios/Flutter/`):
  - `<모드>-<flavor>.xcconfig`: Runner의 각 configuration이 쓴다. `Generated.xcconfig`와 `AppInfo-<flavor>.xcconfig`를 포함만 한다(CocoaPods를 쓰지 않으므로 Pods xcconfig는 없다, #52).
  - `AppInfo-<flavor>.xcconfig`: `PRODUCT_BUNDLE_IDENTIFIER`와 `APP_DISPLAY_NAME`. Xcode 프로젝트(`project.pbxproj`)는 Runner의 bundle ID를 정하지 않는다.
- Xcode에서 scheme이나 configuration을 추가·복제하면 `test/app_display_name_test.dart`가 목록·xcconfig 연결이 어긋난 것을 잡는다.
- `tool/check_ios_flavors.sh`는 9개 configuration(기기·시뮬레이터 SDK 각각)과 3개 scheme에서 `xcodebuild -showBuildSettings`가 계산한 최종 bundle ID·앱 이름·configuration을 `AppInfo-<flavor>.xcconfig`와 비교한다. 위 테스트는 파일 텍스트를 보므로, 다른 xcconfig나 SDK 조건을 거쳐 값이 바뀌는 경우는 이 스크립트가 잡는다. Milestone Full CI의 iOS job이 실행한다.
- 실기기 설치용 서명(Team, flavor별 App ID·프로비저닝)은 아직 정하지 않았다. M1 종료 전 실기기 점검(#16) 때 정한다.

## 3. Android 설정

- **minSdk 28** (Android 9). 14단계 테스트 매트릭스(Android 9~16) 기준이다.
- **권한:** 인터넷, 네트워크 상태, 위치(정확·대략), 카메라, 마이크, 알림(Android 13+).
  - 카메라·GPS는 `uses-feature required="false"`로 두어 해당 하드웨어가 없는 기기도 설치할 수 있다.
  - 저장소·미디어 권한은 쓰지 않는다. `open_filex`가 추가하는 `READ_MEDIA_*`는 Play 사진·동영상 권한 정책 심사 대상이라 `tools:node="remove"`로 제거했다.
    - 웹뷰 파일 업로드는 시스템 파일 선택기(`ACTION_GET_CONTENT`)로 고르고 임시 URI 권한을 받으므로 저장소 권한이 필요 없다(API 28~36). 촬영 선택지는 FileProvider URI를 쓰며, CAMERA 권한이 없으면 크래시하지 않고 선택지에서 빠진다.
    - `open_filex`는 앱 영역(`dataDir`, `getExternalFilesDir`) 밖의 파일을 열 때 미디어·저장소 권한을 직접 요청한다. 이 권한은 제거했으므로 앱 영역 경로만 넘긴다(10단계 다운로드).
    - 매니페스트 테스트(`test/app_config_test.dart`)가 main의 제거 선언(`tools:selector` 없이)과, 다른 source set이나 `uses-permission-sdk-23`으로 다시 선언하지 않는지를 검사한다.
    - 플러그인을 추가하거나 업데이트해서 새로 들어오는 권한은 병합 결과에서만 드러나므로, CI가 빌드한 APK도 검사한다 (#36). `tool/check_android_permissions.sh`가 `aapt2 dump permissions`로 APK의 최종 권한을 읽는다. 금지 권한(`'android.permission.X'`)이 앱이 정의하는 `permission:` 줄 말고 어느 줄에든 나오면 CI가 실패한다. 줄 형식(`uses-permission`, `uses-permission-sdk-23`, 새 태그)에 기대지 않는다.
      - 금지 목록의 원본은 `tool/android_forbidden_permissions.txt`이고, 매니페스트 테스트도 이 파일을 읽는다. 내용은 Dart 테스트와 fixture가 고정하므로, 바꿀 때 함께 고칠 곳은 파일 주석에 적었다.
      - Sub-issue Linux CI는 dev·prod debug APK를(#39에서 prod 추가), Milestone Full CI는 dev·stg·prod release APK를 검사한다. **AAB는 aapt2로 읽을 수 없어 아직 검사하지 않는다.** 15단계(출시 준비)에서 AAB를 빌드하게 되면 `bundletool`로 검사를 넓혀야 한다 (#45). 금지 목록 밖의 새 권한을 막는 허용 목록 검사는 #46에서 다룬다.
      - 덤프를 제대로 읽었는지도 본다. INTERNET·POST_NOTIFICATIONS가 보이는지, `uses-permission`·`uses-permission-sdk-23` 줄마다 이름을 읽었는지 확인한다.
      - 판정 로직은 매번 fixture(`tool/fixtures/aapt2_permissions_*.txt`)로 먼저 확인한다. 금지 fixture(모르는 태그 줄 포함)는 금지 권한 5개만 찾아 실패해야 하고, 정상 fixture는 통과해야 한다. 빈 덤프와 이름을 읽을 수 없는 줄도 실패해야 한다.
      - 이 검사만 잡을 수 있는 경우는 주로 라이브러리가 **`<uses-permission-sdk-23>`** 으로 넣는 권한이다. main의 `<uses-permission tools:node="remove">`는 같은 태그만 지운다. 일반 `<uses-permission>`은 이미 제거된다. 제거 선언을 지우는 회귀는 매니페스트 테스트도 잡는다(Sub-issue CI에서는 테스트가 먼저 돌고, Full CI에서는 두 job이 병렬로 돈다).
      - 실패하면 걸린 덤프 줄을 출력한다. APK 옆에 병합 리포트(`build/app/outputs/logs/manifest-merger-<flavor>-<buildType>-report.txt`)가 있으면 같은 태그 항목의 출처도 출력하고, 없으면 없다고 알린다. 덤프 줄과 **같은 태그**로 main 매니페스트에 selector 없는 `tools:node="remove"`를 추가하거나 플러그인을 바꾼다. 매니페스트 테스트는 `uses-permission-sdk-23`의 제거 선언도 허용한다.
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

- **최소 버전 iOS 16** (`IPHONEOS_DEPLOYMENT_TARGET`).
- **플러그인 연결:** Swift Package Manager만 쓴다. CocoaPods 연동(`Podfile`, `Podfile.lock`, `project.pbxproj`의 Pods 설정, xcconfig의 Pods include)은 #52에서 지웠다.
  - Flutter 3.50.0 기준으로 `flutter_inappwebview_ios`(1.2.0-beta.3)를 포함한 모든 플러그인이 SwiftPM으로 연결된다(#38에서 확인). CocoaPods로는 `Flutter` pod 하나만 설치되고 있었다.
  - SwiftPM을 지원하지 않는 플러그인을 추가하면 Flutter가 `Podfile`을 다시 만들고 `pod install`을 실행한다. 그때는 이 절, `ios/Flutter/<모드>-<flavor>.xcconfig`, `test/app_display_name_test.dart`의 CocoaPods 검사를 함께 고친다. Podfile에는 9개 build configuration 매핑(`project 'Runner', {'Debug-dev' => :debug, ...}`)이 필요하다.
- **`permission_handler` 권한 매크로:** SwiftPM 패키지(`permission_handler_apple` 9.6.5)가 Info.plist의 `NS*UsageDescription` 키를 보고 정한다. 따로 적는 목록은 없다.
  - 지금 켜지는 것: 카메라(`NSCameraUsageDescription`), 마이크(`NSMicrophoneUsageDescription`), 사진(`NSPhotoLibraryUsageDescription`·`NSPhotoLibraryAddUsageDescription`), 위치 사용 중(`NSLocationWhenInUseUsageDescription`), 알림(키 없이 기본으로 켜짐). 예전 Podfile `post_install` 매크로와 같은 목록이다. `photosAddOnly`도 `PERMISSION_PHOTOS`로 켜진다(`PERMISSION_PHOTOS_ADD_ONLY`도 1로 정의되지만 네이티브 코드는 이 값을 쓰지 않는다).
    - #52에서 `swift package dump-package`로 확인했다. 다시 확인하려면 저장소 루트에서 `PERMISSION_HANDLER_VERBOSE=1 swift package --manifest-cache none --package-path ~/.pub-cache/hosted/pub.dev/permission_handler_apple-<버전>/ios/permission_handler_apple dump-package`를 실행한다. stderr의 `resolved permission macros`가 결과다(`--manifest-cache none`이 없으면 캐시된 결과를 써서 아무것도 출력하지 않을 수 있다).
  - 권한을 추가·삭제하려면 Info.plist 키를 바꾼다. 패키지 manifest가 다시 평가되도록 DerivedData를 한 번 지운다(`rm -rf ~/Library/Developer/Xcode/DerivedData`).
  - 패키지는 빌드를 시작한 디렉토리(cwd)에서 위로 올라가며 앱 루트(`pubspec.yaml`과 `ios/*.xcodeproj`가 있는 곳)를 찾고, pbxproj의 `INFOPLIST_FILE`로 Info.plist를 읽는다. 저장소 안에서 실행한 `flutter build`·`flutter run`·`xcodebuild`는 찾는다.
    - **Xcode.app에서 바로 빌드하면 cwd가 `/`라 찾지 못해, 알림을 뺀 모든 권한이 빠진다**(요청하면 항상 `denied`). 저장소 밖에서 절대 경로로 `xcodebuild`를 실행해도 같다.
    - Xcode.app으로 빌드해야 하면 `launchctl setenv PERMISSION_HANDLER_INFO_PLIST <저장소>/ios/Runner/Info.plist`를 설정하고 Xcode를 다시 시작한 뒤 DerivedData를 지운다. 이 값은 사용자 세션 전체에 적용되어 자동 탐색을 대신하므로, 같은 Mac에서 다른 permission_handler 앱을 빌드하기 전에 `launchctl unsetenv PERMISSION_HANDLER_INFO_PLIST`로 지운다.
  - manifest는 build configuration을 모른다. 그래서 flavor별 Info.plist를 두면 권한이 모든 flavor의 합집합이 된다. flavor마다 권한을 달리하려면 `permission_handler.yaml`과 `dart run permission_handler_apple:select <flavor>`가 필요하다(#53에서 flavor별 Info.plist를 고를 때 참고).
- **Info.plist:**
  - 권한 문구: 카메라, 마이크, 위치(사용 중), 사진 보관함 읽기·추가.
- **`photos` 권한:** iOS에서는 설정대로 요청한다. 다만 웹 파일 업로드에는 사진 보관함 권한이 필요 없다(시스템 피커). 보관함을 네이티브로 직접 읽는 기능이 있을 때만 `photos`를 쓴다. iOS 14+의 `limited` 처리는 권한 요청을 구현하는 단계에서 정한다.
  - `LSApplicationQueriesSchemes`: `tel`, `sms`, `mailto`.
  - `NSAllowsLocalNetworking`: 로컬 테스트 페이지용. App Store 심사에서 허용되는 예외다.
- **macOS에서 처음 빌드할 때:** CocoaPods는 필요 없다. `flutter build ios --flavor <flavor>`를 실행하면 SwiftPM이 패키지를 해석한다. `Package.resolved`(`Runner.xcodeproj`·`Runner.xcworkspace` 아래)가 바뀌면 커밋한다.
  - #38에서 처음 macOS로 빌드할 때는 CocoaPods 연동이 함께 생겨 커밋했고, #52에서 `pod deintegrate`로 지웠다. 예전 체크아웃에 남은 `ios/Pods/`는 지워도 된다(`.gitignore` 대상).

## 5. 앱 코드

- `lib/config/app_config.dart`: 0단계 스키마를 그대로 옮긴 불변 모델이다.
  - 생략한 값은 스키마 기본값으로 채운다.
  - 모르는 enum 값이나 틀린 타입은 JSON 경로와 함께 시작 시 바로 실패한다.
  - 스키마에 없는 키(오타 포함)는 값을 읽기 전에 경로를 모두 모아 실패한다(#4). 오타 난 키가 조용히 무시되어 기본값이 쓰이는 것을 막고, 필수 키 오타(`startURL`)도 "필요합니다" 대신 오타 위치로 알린다.
    - 아는 키 목록(`AppConfig.knownKeys`)은 최소 설정으로 모델을 한 번 만들며 읽은 키를 기록해 얻는다. 그래서 모델은 스키마의 모든 키를 조건 없이 읽어야 한다.
    - 이 목록이 스키마의 object별 속성과 정확히 같은지, `properties`로 이어지는 모든 object가 `additionalProperties: false`인지는 테스트가 확인한다. 스키마와 모델 중 한쪽만 고치면 테스트가 실패한다.
    - 배열 원소 object나 `allOf`·`anyOf`·`oneOf`로 키를 정의하는 스키마는 로더가 지원하지 않으며, 테스트가 막는다.
    - 최소 설정이 모델의 필수 키나 읽기 단계 검사(범위·형식 포함)와 어긋나면 `StateError`(코드 버그)로 실패한다. 필수 키나 읽기 단계 검사를 늘릴 때 함께 고친다.
  - 아는 키에 `null`을 직접 적으면 기본값을 쓰지 않고 실패한다(생략은 허용).
  - 로더가 다시 검사하는 것: 모르는 키, 필수 키, 타입, enum 값, 색상 형식, URL에 scheme·host가 있는지, `allowedHosts`가 비었는지, 강제 업데이트의 `checkUrl`, prod 제약, 그리고 아래 범위·형식 제약(#5).
  - **범위·형식 (#5):** 스키마의 값 제약도 로더가 다시 검사한다. CI를 거치지 않은 빌드가 `popup.maxDepth: 0`(팝업이 안 열림)이나 `splash.maxWaitMs: -1`(스플래시 즉시 타임아웃) 같은 값으로 오류 없이 시작하는 것을 막는다.
    - `minimum`·`maximum`: `*Ms` 값 0~3600000(1시간), `popup.maxDepth` 1~10, `network.retry.maxAttempts` 0 이상. `_Reader.integer(min:, max:)`로 읽고, 모델 기본값도 같이 검사한다.
      - `*Ms` 상한(`$defs.ms`의 `maximum`)은 #5에서 스키마에 새로 넣었다. 1시간은 실사용에 충분한 정책 값이다(넘침 지점은 약 9.2e15ms).
        - 상한이 없으면 아주 큰 값에서 `Duration`의 마이크로초 계산이 int64를 넘어 음수 지연이 된다. 그러면 `-1`과 같은 즉시 타임아웃이 난다.
        - `network.retry.maxAttempts`에는 아직 상한이 없다.
    - `pattern`: 모든 flavor의 `startUrl`은 원문이 소문자 `http://`·`https://`로 시작해야 한다. 스키마 pattern은 대소문자를 구분하는데 `Uri`는 scheme을 소문자로 바꾸므로, 파싱 전 원문으로 본다. `allowedHosts`·`externalHosts`·`deeplink.domains`의 원소는 `hostPattern`을 따라야 한다.
    - `uniqueItems`: 위 세 호스트 목록과 `permissions.requestOnLaunch`의 중복을 거부한다. 그래서 `requestOnLaunchOn()`이 같은 권한을 두 번 돌려주지 않는다. 중복은 원소 형식·enum 검사 뒤에 보므로, `["bogus", "bogus"]`는 "알 수 없는 값"으로 알린다.
    - `minLength`: `app.name`의 빈 문자열을 거부한다.
    - URL(`startUrl`, `checkUrl`): scheme·host가 없거나 포트가 음수이거나 int 범위를 넘으면 `URL 형식 오류`로 실패한다.
      - `Uri.tryParse`는 큰 포트를 받아 두었다가 `port`를 처음 읽을 때 `FormatException`을 던진다.
      - 로더가 미리 읽어 거르지 않으면 이 예외가 `AppConfigException` 밖으로 새어, 오류 화면 대신 앱이 죽는다.
    - 오류는 경로와 값을 함께 알린다. 문자열 값은 JSON 표기로 적어 빈 문자열과 개행이 보이게 한다 (예: `$.popup.maxDepth: 1 이상 10 이하여야 합니다 (0)`, `$.app.allowedHosts[1]: 중복된 값 ("example.com")`).
    - 스키마와 로더가 어긋나지 않는지는 테스트가 스키마를 읽어 확인한다.
      - **스냅샷:** 스키마 전체(배열 원소 `items`, `if`/`then` 안 포함)의 값 제약을 `<경로> <키워드>` → 값으로 뽑는다. 이 스냅샷이 테스트에 손으로 적은 "로더가 검사하도록 맞춘 목록"과 정확히 같아야 한다.
        - 스키마에 제약을 더하거나 바꾸면 테스트가 실패한다(예: `checkUrl`에 `pattern`, prod `then`에 `maximum`이나 `additionalProperties`). 그때 로더 검사와 목록을 함께 고친다.
        - `type`·`default`는 스냅샷 범위 밖이다.
      - **동작:** 필드마다 값을 넣어 본다. 스키마와 로더 중 어느 쪽만 바뀌어도 잡는다.
        - `minimum`·`maximum`은 경계값과 ±1을 넣는다. 경계가 없는 쪽은 아주 큰(작은) 값이 통과하는지 본다.
        - `uniqueItems`는 중복을, `minLength`는 빈 문자열을 넣는다. 제약이 없는 문자열은 빈 문자열이 통과하는지 본다.
        - `hostPattern` 원소를 넣어 본다.
        - enum 필드는 스키마의 모든 값을 받는지 본다. 모르는 값 오류에 나오는 허용값 목록이 스키마 enum과 같은지도 본다.
      - **문자열:** 로더의 pattern 문자열(`AppConfig.schemaPatterns`)이 스키마와 같은지 본다.
      - **키워드:** 스키마가 로더가 모르는 키워드(`maxLength`, `exclusiveMinimum` 등)를 쓰거나, `$ref` 옆에 값 제약을 두면(2020-12에서는 둘 다 적용되므로 단순 병합과 의미가 다르다) 테스트가 실패한다.
  - CI와 로더의 판정이 다른 경우
    - **로더가 더 느슨한 것:** `format: uri`의 세부 문법뿐이다(값 제약 기준, `type`은 #4 테스트 영역). 로더는 scheme·host·포트만 본다. 이것은 CI가 막는다.
      - 로더는 CI가 거부하는 URL을 고쳐 쓰기도 한다(`\`를 `/`로, `%`·`#` 인코딩, 끝 개행을 `%0A`로). 그래서 CI를 거치지 않으면 다른 URL을 로딩할 수 있다.
      - `tool/validate_config.sh`가 `check-jsonschema`로 번들 설정 파일을 검증한다.
      - `format: uri` 검사 패키지(`rfc3986-validator`)가 빠지면 잘못된 URI도 통과한다. 그래서 스크립트는 fixture가 uri 형식 오류 하나로만 실패하는지 확인한다.
      - 버전은 `tool/requirements-ci.txt`에 고정했다.
    - **로더가 더 엄격한 것:** 아래 입력은 CI는 통과하지만 로더는 거부한다. 번들 설정은 `flutter test`가 로더로 읽으므로, 이런 값을 넣어도 CI에서 함께 걸린다.
      - 정수 자리의 `5.0`·`1e3`: jsonschema는 정수로 보지만, Dart `jsonDecode`는 double을 돌려준다.
      - 64비트를 넘는 정수
      - host가 없는 URI(`urn:isbn:...`), int 범위를 넘는 포트
  - prod 제약(https, 개발용 옵션 금지)을 한 번 더 검사한다.
  - **권한 (#3):** 설정 파일은 플랫폼 공통이라 플랫폼마다 건너뛸 권한이 있다.
    - 권한 요청 코드(8·9·11·13단계)는 시작 시 목록을 `PermissionsConfig.requestOnLaunchOn(defaultTargetPlatform)`으로만 받는다. 설정 원본 목록은 공개하지 않는다.
    - 기능을 쓸 때 요청하는 경로도 `AppPermission.isRequestableOn(defaultTargetPlatform)`을 먼저 확인한다.
    - `isRequestableOn`은 매니페스트·플러그인 제약 때문에 그 플랫폼에서 요청 자체를 건너뛸지만 정한다(플랫폼 단위). API 레벨에 따른 실제 상태는 permission_handler가 돌려준다. 지금은 Android의 `photos`만 `false`다.
    - `deniedGuide`는 `isPermanentlyDenied`일 때만 설정 앱 이동을 안내한다.
- `lib/main.dart`: flavor 설정을 읽고 확인 화면을 띄운다. 2단계에서 `AppWebView`로 바꾼다.
  - 설정을 읽지 못하면(`AppConfigException`) `ConfigErrorApp`을 띄우고 예외를 `FlutterError.reportError`로 보고한다. 예외 내용은 debug에서만 보여 준다.
  - `AppConfig.load`는 asset 누락, JSON 형식 오류, 최상위 타입 오류를 포함해 모든 설정 오류에 파일 경로를 붙여 `AppConfigException`으로 던진다. 그 밖의 예외는 코드 버그로 보고 잡지 않는다.
- `test/`: 세 설정 파일 로딩, 기본값, 검증 실패 케이스, 플랫폼별 권한 목록, 모르는 키와 스키마·모델 일치(#4), 범위·형식 제약과 스키마 일치(#5), 확인 화면과 설정 실패 화면 위젯 테스트(70개).

## 6. 확인 결과

| 항목 | 결과 |
|---|---|
| `flutter analyze` | 이슈 없음 |
| `flutter test` | 70개 통과 (#5 반영 후) |
| `flutter build apk --debug --flavor dev` / `stg` | 성공 |
| `flutter build apk --release --flavor prod` (R8) | 성공 |
| Android 에뮬레이터(API 36.1)에서 dev·prod 실행 | 설정 확인 화면 정상, dev·prod 함께 설치됨 |
| 병합된 prod 매니페스트 | 권한 8개(+ AndroidX 내부 권한), minSdk 28, targetSdk 36 |
| iOS 시뮬레이터(iPhone 17) dev·stg·prod 빌드·실행 (#38) | 세 flavor 함께 설치, 홈 화면 이름 U4 DEV·U4 STG·U4, 설정 확인 화면의 flavor 정상 |
| iOS 실기기 실행 | **미확인** |
| Android 실기기 실행 | **미확인** (에뮬레이터로만 확인) |

완료 기준 "양쪽 실기기에서 실행"은 iOS 실기기 확인이 남아 있다.
