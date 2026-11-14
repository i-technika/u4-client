# 0단계: 요구사항·설정 스키마 확정

> 원본: 「Flutter 웹 하이브리드 앱 플랫폼 설계 분석」 문서의 5장 단계별 작업 순서 중 0단계

| 항목 | 내용 |
|---|---|
| 목표 | 3장(웹뷰 별도 구현 항목)·4장(앱 옵션) 중 1차 범위를 확정하고, 이후 단계가 공통으로 쓰는 설정 구조를 고정한다 |
| 주요 작업 | 범위 확정, `AppConfig` 모델 정의, flavor(dev/stg/prod) 구성 |
| 산출물 | 설정 스키마 [`config/app_config.schema.json`](../config/app_config.schema.json), flavor별 설정 [`config/`](../config/), 기능 테스트 페이지 [`test-page/index.html`](../test-page/index.html) |
| 완료 기준 | 설정 스키마 + 기능 테스트용 HTML 페이지 |
| 선행 단계 | 없음 (1단계 프로젝트 셋업의 선행 단계) |

## 1. 기본 방향 (요약)

- 웹뷰는 `flutter_inappwebview`를 쓴다. 공식 `webview_flutter`는 `window.open` 멀티 윈도우와 JS 다이얼로그 오버라이드가 약하다.
  - 안정판 6.1.5가 정체 상태이므로 **버전을 고정**하고, 웹뷰 호출부를 `WebViewAdapter` 레이어로 감싼다.
- 네이티브 연동은 **표준 웹 API 폴리필**로 감싼다. 웹 코드는 브라우저 표준 그대로 두고, 앱이 웹뷰 콜백이나 폴리필로 가로챈다.
- 앱 전용 기능은 `window.App.*` 네임스페이스와 `appready` 이벤트로 따로 노출한다(3단계).
- 메인 화면과 팝업은 같은 `AppWebView` 위젯을 쓴다. 그래야 Alert·GPS·파일 처리가 팝업 안에서도 똑같이 동작한다.

## 2. 범위 확정

### 우선순위와 범위 규칙

| 우선순위 | 의미 | 1차 범위 |
|---|---|---|
| P0 | 없으면 일반 웹사이트가 깨짐 | **필수** |
| P1 | 대부분 서비스에 필요 | **포함** |
| P2 | 서비스에 따라 필요 | 단계표에 들어간 항목(`getUserMedia`, `window.print`)만 포함하고 나머지는 **보류**. 보류 항목도 나중에 브릿지를 붙일 수 있게 메시지 규약은 공통으로 둔다 |

요청받은 4가지 기능(팝업 윈도우, GPS, 파일 오픈, Alert 시리즈)은 모두 1차 범위다.

### A. 창·내비게이션

| 항목 | 우선순위 | 범위 | 구현 단계 |
|---|---|---|---|
| `window.open` / `target=_blank` | P0 | 필수 | 7 |
| `window.close()` | P0 | 필수 | 7 |
| Android 뒤로가기 (히스토리 → 팝업 → 종료 확인) | P0 | 필수 | 7 |
| iOS 스와이프 뒤로가기 | P1 | 포함 | 2 |
| 외부 도메인 링크 (화이트리스트 / 외부 브라우저 / 인앱 브라우저) | P0 | 필수 | 2 |
| 새로고침 (Pull-to-refresh) | P1 | 포함 | 2 |
| 기본 앱 스킴 (`tel:` / `sms:` / `mailto:` / `geo:`) | P0 | 필수 | 2 |

### B. 파일·미디어

| 항목 | 우선순위 | 범위 | 구현 단계 |
|---|---|---|---|
| 파일 업로드 (`accept` / `multiple` / `capture`) | P0 | 필수 | 8 |
| 파일 다운로드 (Content-Disposition) | P0 | 필수 | 10 |
| `blob:` / `data:` 다운로드 | P1 | 포함 | 10 |
| 동영상 전체화면 | P1 | 포함 | 11 |
| iOS 인라인 재생 / 자동재생 | P1 | 포함 | 11 |
| `getUserMedia` (카메라/마이크) | P2 | 포함 | 11 |
| `window.print()` | P2 | 포함 | 10 |
| 이미지 롱프레스 저장 | P2 | 보류 | — |

### C. 웹 API 폴리필

| 표준 API | 연결 패키지 | 우선순위 | 범위 | 구현 단계 |
|---|---|---|---|---|
| `navigator.geolocation` | `geolocator` | P0 | 필수 | 9 |
| `navigator.share` | `share_plus` | P1 | 포함 | 10 |
| `navigator.clipboard` | `Clipboard` | P1 | 포함 | 10 |
| `Notification` / Web Push | `firebase_messaging` | P1 | 포함 | 13 |
| `navigator.vibrate` | `HapticFeedback` / `vibration` | P2 | 보류 | — |
| Wake Lock API | `wakelock_plus` | P2 | 보류 | — |
| DeviceOrientation / Motion | `sensors_plus` | P2 | 보류 | — |
| WebAuthn / Passkey | — | P2 | 보류 | — |
| Contact Picker, Web Bluetooth/NFC/USB | — | P2 | 보류 | — |

### D. 세션·네트워크·안정성

| 항목 | 우선순위 | 범위 | 구현 단계 |
|---|---|---|---|
| 쿠키 영속성 (백그라운드 진입 시 flush) | P0 | 필수 | 12 |
| 서드파티 쿠키 | P0 | 필수 | 2 |
| 메인↔팝업 세션 공유 | P0 | 필수 | 7 |
| localStorage / IndexedDB | P0 | 필수 | 2 |
| 오프라인 / 로딩 에러 페이지 + 재시도 | P0 | 필수 | 12 |
| HTTP (비SSL) 허용 (dev 전용) | P1 | 포함 | 1 |
| SSL 오류 처리 (운영 거부, dev 옵션) | P1 | 포함 | 2 |
| 렌더 프로세스 크래시 복구 | P1 | 포함 | 12 |
| 앱 라이프사이클 이벤트 (`pause` / `resume`) | P1 | 포함 | 12 |
| 딥링크 / Universal Link / App Link | P1 | 포함 | 13 |
| HTTP Basic 인증 | P2 | 보류 | — |
| Service Worker / PWA 캐시 (iOS App-Bound Domains) | P2 | 보류 | — |

### E. 화면·입력 UX

| 항목 | 우선순위 | 범위 | 구현 단계 |
|---|---|---|---|
| Safe area (CSS 변수 주입, `env()` 폴백) | P0 | 필수 | 5 |
| 키보드에 가려지는 입력창 | P0 | 필수 | 1~2 |
| User-Agent 접미사 | P0 | 필수 | 2 |
| 원격 디버깅 (debug 빌드만) | P0 | 필수 | 2 |
| 시스템 글꼴 크기 고정 (`textZoom`) | P1 | 포함 | 2 |
| 핀치 줌 / 텍스트 선택 / 링크 미리보기 / 바운스 on·off | P1 | 포함 | 2 |
| 다크모드 전달 | P1 | 포함 | 5 |

### 부가 기능 (13단계)

FCM/APNs 푸시, 토큰 웹 전달, 알림 탭 → URL 이동, App/Universal Link, 강제 업데이트를 포함한다.

> iOS 심사 4.2(Minimum Functionality)에 대비해, 웹사이트를 감싸기만 한 앱으로 보이지 않도록 푸시·오프라인 화면·네이티브 공유를 1차 범위에 둔다.

## 3. 설정 스키마 (`AppConfig`)

### 파일 구성

```
config/
├── app_config.schema.json   # JSON Schema (draft 2020-12): 구조·기본값·flavor별 제약
├── app_config.dev.json
├── app_config.stg.json
└── app_config.prod.json
```

- 설정은 flavor마다 `app_config.<flavor>.json` 파일 하나로 관리한다. 1단계에서 Flutter 프로젝트를 만들면 flavor에 맞는 파일을 asset으로 번들한다.
- 각 파일은 `"$schema": "./app_config.schema.json"`을 선언하므로 에디터에서 자동완성과 검증이 된다.
- 스키마에 없는 키는 허용하지 않는다(`additionalProperties: false`). 오타 난 옵션이 조용히 무시되는 일을 막기 위해서다.

### 그룹 구성

| 그룹 | 키 | 주요 옵션 |
|---|---|---|
| 기본 | `app` | `name`(Alert 제목), `startUrl`, `allowedHosts[]`, `externalHosts[]`, `userAgentSuffix` |
| 스플래시 | `splash` | `minDisplayMs`, `closeTrigger`, `delayAfterLoadMs`, `maxWaitMs`, `fadeOutMs`, `bgColor`, `image`, `showProgress` |
| 시스템 UI | `systemUi` | `statusBar`, `navigationBar`, `safeAreaHandling`, `immersive`, `allowWebControl` |
| 테마 | `theme` | `themeMode`, `propagateToWeb`, `allowWebOverride` |
| 화면 | `screen` | `orientation`, `allowWebOrientationChange`, `textZoomFixed`, `pinchZoom`, `textSelection`, `longPressMenu`, `overscroll`, `pullToRefresh` |
| 내비게이션 | `navigation` | `androidBack`, `iosSwipeBack`, `externalLinkMode` |
| 팝업 | `popup` | `presentation`, `toolbar`, `maxDepth` |
| 다이얼로그 | `dialog` | `style`, `labels` |
| 권한 | `permissions` | `requestOnLaunch[]`, `deniedGuide` |
| 네트워크/보안 | `network` | `offlinePage`, `errorPage`, `retry`, `allowHttp`, `ignoreSslErrors`, `debuggable`, `secureScreen`, `clearCacheOnLaunch`, `cacheMode` |
| 부가 | `extras` | `push`, `deeplink`, `forceUpdate`, `locale` |

옵션별 값과 기본값은 스키마의 `description`·`default`에 적어 두었다.

### 규칙

1. **링크 판정:** `externalHosts`에 있으면 외부로 연다(`allowedHosts`보다 우선). 그다음 `allowedHosts`에 있으면 내부 웹뷰에서 열고, 어디에도 없으면 외부로 연다. 외부로 여는 방식은 `externalLinkMode`(`system` / `inAppBrowser` / `block`)를 따른다. `*.example.com`처럼 와일드카드 서브도메인을 쓸 수 있다.
2. **`prod` 제약:** `flavor`가 `prod`이면 `network.allowHttp`, `network.ignoreSslErrors`, `network.debuggable`이 모두 `false`여야 하고, `startUrl`은 `https://`로 시작해야 한다. 스키마의 `if/then`으로 강제한다.
3. **웹 런타임 변경:** 아래 옵션은 해당 허용 플래그가 켜져 있을 때만 웹이 브릿지로 바꿀 수 있다. 브릿지 API 자체는 3·5단계에서 구현한다.

   | 웹 API (예정) | 허용 플래그 |
   |---|---|
   | `App.ui.setStatusBar({...})` / `setNavigationBar` | `systemUi.allowWebControl` |
   | `App.theme.set()` | `theme.allowWebOverride` |
   | `App.screen.setOrientation()` | `screen.allowWebOrientationChange` |
   | `App.splash.hide()` | `splash.closeTrigger = webSignal`일 때 사용 |

4. **스플래시 타이밍:** 닫히는 시점은 `max(시작 + minDisplayMs, 닫힘 조건 충족 + delayAfterLoadMs)`이고, 그 전이라도 `maxWaitMs`가 지나면 강제로 닫는다. 이 조합으로 "로딩 후 N초"와 "시작 후 N초 + 로딩 완료" 두 해석을 모두 지원한다. SPA는 초기 렌더가 늦으므로 `webSignal`이 가장 정확하다.
5. **Safe area:** Android WebView 140 미만은 `env(safe-area-inset-*)` 값이 틀리므로 `safeAreaHandling` 기본값은 `css`(`--safe-area-inset-*` 변수 주입, `env()`는 폴백)다. 웹은 `viewport-fit=cover`를 선언해야 한다.

### Dart 모델 (1단계에서 구현)

- 스키마 그룹마다 불변 클래스 하나(`AppConfig`, `SplashConfig`, `SystemUiConfig` …)를 두고, `fromJson`에서 스키마 기본값을 채운다.
- enum 값은 Dart enum으로 매핑한다. 모르는 값이 들어오면 시작 시 바로 실패하게 한다.
- 앱 시작 시 flavor 설정 파일을 읽고, 위 `prod` 제약을 한 번 더 검사한다(스키마 검증을 빠뜨린 빌드 대비).

## 4. 기능 테스트 페이지

[`test-page/index.html`](../test-page/index.html)은 의존성 없는 단일 HTML 파일이다. 1단계부터 개발 빌드의 `startUrl`로 띄워 단계마다 이 페이지로 검증하고, 단계가 진행될 때마다 버튼을 늘린다.

- 브라우저에서 그대로 열어도 동작하므로, 같은 버튼을 브라우저와 앱에서 눌러 결과를 비교할 수 있다.
- `?popup=<depth>`로 열리면 팝업 모드가 되어 `window.opener`, `postMessage`, `window.close()`, 중첩 팝업을 테스트한다.
- 상단에 UA, `window.App` 존재 여부, `appready` 수신, Safe area 값(`env()`와 주입 CSS 변수), `prefers-color-scheme`를 표시한다.
- 모든 결과는 하단 로그에 시간순으로 남는다.

| 섹션 | 검증 단계 |
|---|---|
| 환경 정보, 브릿지 | 2, 3, 5 |
| 다이얼로그 (alert / confirm / prompt / beforeunload) | 6 |
| 팝업 (window.open, `_blank`, 중첩, opener 통신) | 7 |
| 링크·스킴 (tel / sms / mailto / geo / 외부 도메인) | 2 |
| 파일 업로드 | 8 |
| 위치 | 9 |
| 다운로드·공유·클립보드·인쇄 | 10 |
| 미디어 | 11 |
| 저장소·쿠키, 라이프사이클 | 2, 12 |

Content-Disposition 다운로드는 서버 응답 헤더가 필요하므로 10단계에서 테스트 서버 URL을 페이지에 추가한다.

## 5. 확인이 필요한 사항

아래 값은 설정 파일에 임시값(`example.com` 등)으로 들어가 있다. 1단계 전에 확정해야 한다.

- [ ] 앱 이름(`app.name`), 번들 ID / applicationId
- [ ] flavor별 `startUrl`, `allowedHosts`, `externalHosts`
- [ ] 최소 지원 OS: 테스트 매트릭스 기준 Android 9(API 28) / iOS 16 제안
- [ ] 스플래시 닫힘 조건: 웹이 `App.splash.hide()`를 호출할 수 있는지(`webSignal`), 안 되면 `onLoadStop`
- [ ] 팝업 표시 방식(`push` / `modal` / `sheet`)과 다이얼로그 스타일(`platform` 제안)
- [ ] 푸시 사용 여부, 딥링크 도메인, 강제 업데이트 체크 URL
- [ ] 보류한 P2 항목 중 서비스에 필요한 것 (예: 생체인증·Passkey, 진동, 화면 꺼짐 방지)
- [ ] 캡처 방지(`secureScreen`) 필요 여부

## 다음 단계

1단계 프로젝트 셋업: 패키지 버전 고정, 번들 ID, minSdk/iOS 버전, Manifest·Info.plist 권한 문구, 기본 스킴용 Android `<queries>`, FileProvider 설정. 완료 기준은 빈 앱이 양쪽 실기기에서 실행되는 것이다.
