# 프로젝트: U4 웹 하이브리드 앱 클라이언트 (Flutter)

> 이 문서가 프로젝트 규칙의 단일 기준(Single Source of Truth)이다.
> 작업 방식(에픽·서브이슈, 스킬, CI)은 i-technika/altcalc-fx991과 같게 맞춘다 (#31).

## 0. 응답 및 작업 언어
- 모든 설명, 계획 수립, 코드 주석, 커밋 메시지 본문, PR/이슈 본문은 **한국어**로 작성한다.
- 현재 진행 단계와 완료 기준은 항상 [milestone.md](milestone.md)와 GitHub 이슈를 기준으로 삼는다.
- 단계별 설계·결정 내용은 `docs/phase-<N>-*.md`에 남긴다 (예: [docs/phase-1-setup.md](docs/phase-1-setup.md)).

## 1. 핵심 아키텍처 및 기술 스택
- **프레임워크:** Flutter 3.50.0 (`.fvmrc`, `environment.flutter` 3.50.x) — Android / iOS
  - Material 위젯은 분리 패키지 `material_ui`로 제공된다. **`import 'package:material_ui/material_ui.dart';`** 를 쓴다.
- **웹뷰:** `flutter_inappwebview` 6.2.0-beta.3 고정 (안정판 6.1.5는 AGP 9에서 빌드 실패 — [docs/phase-1-setup.md](docs/phase-1-setup.md) 1장). 웹뷰 호출부는 `WebViewAdapter` 레이어로 감싼다.
- **네이티브 연동:** 웹 코드는 브라우저 표준 그대로 두고, 앱이 웹뷰 콜백이나 **표준 웹 API 폴리필**로 가로챈다. 앱 전용 기능은 `window.App.*` 네임스페이스와 `appready` 이벤트로 노출한다 (M3).
- **메인 화면과 팝업은 같은 `AppWebView` 위젯**을 쓴다. Alert·GPS·파일 처리가 팝업 안에서도 똑같이 동작해야 한다.
- **설정:** `config/app_config.<flavor>.json`(dev/stg/prod)을 `AppConfig`로 읽는다. 스키마는 `config/app_config.schema.json`.
  - Android는 `productFlavors`, iOS는 Xcode scheme(`dev`/`stg`/`prod`)과 build configuration(`Debug-dev` 등)으로 나누고, 둘 다 `--flavor dev|stg|prod`로 고른다 (#38).
  - iOS bundle ID·앱 이름은 `ios/Flutter/AppInfo-<flavor>.xcconfig`에 있다. 설정 JSON의 `app.name`이나 Android applicationId를 바꾸면 같이 고친다.
  - release 빌드는 flavor를 지정하지 않으면 시작하지 않는다.
- 직접 의존성은 정확한 버전으로 고정하고, 올릴 때는 PR로 하나씩 올린다.

## 2. 디렉토리 구조
- `lib/main.dart`: 진입점. 설정 로딩 실패 시 `ConfigErrorApp`을 띄운다.
- `lib/config/app_config.dart`: `AppConfig` 모델과 JSON 로더(`_Reader`)
- `config/`: 설정 스키마와 flavor별 설정
- `docs/`: 단계별 설계·결정 문서 (`phase-0-requirements.md`, `phase-1-setup.md`, ...)
- `test/`: Dart 테스트. 공용 도구는 `test/helpers.dart` (#10에서 추가)
- `test-page/`: 단계별 검증용 기능 테스트 HTML 페이지 (실행 방법은 README)
- `tool/`: CI 보조 스크립트 (`validate_config.sh`: 설정 스키마 검증, #4 / `check_android_permissions.sh`: APK 금지 권한 검사, #36 / `check_ios_flavors.sh`: iOS flavor별 실제 bundle ID·앱 이름 확인, macOS 전용, #38 / `check_android_app_label.sh`: APK 런처 이름과 `app.name` 비교, #39)
- `android/`, `ios/`

## 3. 코딩 원칙
- 설정 값은 스키마(`config/app_config.schema.json`)와 Dart 모델을 함께 고친다. 새 설정에는 기본값과 로딩 테스트를 둔다.
  - 로더는 스키마에 없는 키를 거부하므로, 모델은 스키마의 모든 키를 값과 상관없이 조건 없이 읽는다 (#4).
- 플랫폼별로 동작이 다르면 코드 주석과 `docs/`에 적는다.
- 커밋 전 항상 `flutter analyze`(이슈 0건)와 `flutter test`(전부 통과)를 확인한다.
- 동작 확인 범위는 `flutter analyze`, `flutter test`, **Android 에뮬레이터**까지다. iOS 실기기·시뮬레이터 확인은 macOS에서 iOS scheme을 구성할 때 한꺼번에 하므로 이슈별로 하지 않고, PR에 미확인 항목으로도 적지 않는다. 단, 변경이 iOS 전용 코드(`ios/`, Info.plist, Podfile)에만 있어 Android로 전혀 검증되지 않으면 그 사실을 한 줄로 알린다.

## 4. 로컬 개발 환경 메모
- Flutter SDK가 시스템 PATH에 없을 수 있다. `flutter`를 찾지 못하면 Bash에서
  `export PATH="/c/Users/fmthead/develop/flutter/bin:$PATH"` 후 실행한다.
- adb: `/c/Users/fmthead/AppData/Local/Android/Sdk/platform-tools/adb.exe`
- macOS(iOS 작업): Flutter 3.50.0은 `~/develop/flutter-3.50.0`에 있다(`~/flutter`는 다른 버전). `export PATH="$HOME/develop/flutter-3.50.0/bin:$PATH"` 후 실행한다. Android SDK는 `~/Library/Android/sdk`.
- GitHub CLI(`gh`)로 이슈/PR/프로젝트를 관리한다. 저장소: `i-technika/u4-client`
- `gh`에 여러 줄 본문을 넘길 때는 셸 이스케이프 깨짐을 막기 위해 **반드시 임시 파일 + `--body-file`** 을 사용한다.
- Python으로 한글을 출력할 때는 `python -I -X utf8`을 쓴다 (`-I`는 `PYTHONIOENCODING`을 무시한다).

## 5. 개발 워크플로우 (스킬)
마일스톤 에픽 → 서브이슈 구조로 진행하며, 아래 프로젝트 스킬을 사용한다 (`.claude/skills/`).

| 명령 | 용도 |
|---|---|
| `/open-ms <에픽번호>` | `main`에서 `milestone/m<N>` 분기 + 마일스톤 Draft PR 생성 |
| `/fix-issue <서브이슈번호>` | 서브이슈 구현 → PR → 적대적 리뷰 2라운드 → 마일스톤 브랜치 머지 → 이슈 Close |
| `/close-ms <에픽번호>` | 마일스톤 PR Ready 전환 → 멀티플랫폼 CI → `main` 머지 |

### 브랜치/PR 규칙
- 마일스톤 브랜치: `milestone/m<N>` (base: `main`, Draft PR로 유지 → Draft 동안 CI 미실행)
- 서브이슈 브랜치: `issue/<번호>-<영문-키워드>` (base: `milestone/m<N>`)
- 서브이슈 PR 제목: `[M<N>-<순번>] <이슈 제목> (#<번호>)` — 이슈 제목의 `[M2-1]` 접두사를 그대로 사용
- 에픽 이슈 제목: `[M<N>] <마일스톤 이름>` / GitHub 마일스톤 이름: `M<N>: <마일스톤 이름>`
- 라벨: 에픽 `milestone`, 서브이슈 `sub-issue` (+ 필요하면 `bug`·`enhancement`) / 이슈 타입: 에픽 Feature, 서브이슈 Task·Bug·Feature / 프로젝트: `U4 Client` (#8)
- 서브이슈 PR은 기본 브랜치가 아닌 마일스톤 브랜치로 머지되므로 `Closes #N`으로 **이슈가 자동 Close되지 않는다.** 머지 후 직접 `gh issue close`한다.
- 머지 방식: 서브이슈 PR → 마일스톤 브랜치는 squash, 마일스톤 PR → `main`은 merge 커밋 (`main` ruleset이 merge만 허용)
- CI: 마일스톤 브랜치 대상 PR → `Sub-issue Linux CI`, `main` 대상 PR(Ready) → `Milestone Full Multi-Platform CI`
- PR 리뷰에서 범위 밖 지적이 나오면 사용자 확인 후 같은 마일스톤(또는 해당 마일스톤)의 서브이슈로 등록한다.

### M1 예외
- M1(프로젝트 셋업)은 이 규칙을 도입하기 전에 시작해 `step1/project-setup` 브랜치(PR #12)와 `fix/<이슈>-<slug>` 브랜치로 진행 중이다. M1은 그대로 마무리하고, M2부터 위 규칙을 쓴다.
- 열린 PR의 head 브랜치 이름을 GitHub에서 바꾸면 그 PR이 닫히고 다시 열 수 없다. 이름을 바꿔야 하면 먼저 사용자에게 알린다.

### GitHub Project #8 (U4 Client) 식별자
- Project ID: `PVT_kwHOBMwL0c4Bsrv0` / Owner: `i-technika`
- Status 필드 ID: `PVTSSF_lAHOBMwL0c4Bsrv0zhq4uqM`
  - Todo `f75ad846` / In Progress `47fc9ee4` / Done `98236657`
- 이슈 타입 ID: Task `IT_kwDOBMwL0c4PCk6t` / Bug `IT_kwDOBMwL0c4PCk6u` / Feature `IT_kwDOBMwL0c4PCk6v`
