# u4-client

`flutter_inappwebview` 기반 웹 하이브리드 앱 클라이언트입니다. 웹 코드는 브라우저 표준 그대로 두고, 네이티브 연동은 웹뷰 콜백과 표준 웹 API 폴리필로 처리합니다.

## 진행 상황

| 단계 | 작업 | 문서 |
|---|---|---|
| 0 | 요구사항·설정 스키마 확정 | [docs/phase-0-requirements.md](docs/phase-0-requirements.md) |
| 1 | 프로젝트 셋업 | [docs/phase-1-setup.md](docs/phase-1-setup.md) |

전체 마일스톤(M1~M15)은 [milestone.md](milestone.md)에 있습니다. 각 마일스톤은 GitHub 마일스톤·에픽 이슈(`[M<N>]`)와 1:1로 대응하고, 진행 상태는 프로젝트 보드 [U4 Client](https://github.com/users/i-technika/projects/8)에서 봅니다.

## 작업 방식

마일스톤 에픽 → 서브이슈 구조로 진행합니다. 규칙의 기준은 [CLAUDE.md](CLAUDE.md)입니다.

- 마일스톤 브랜치 `milestone/m<N>`을 `main`에서 만들고, Draft PR로 유지합니다.
- 서브이슈는 `issue/<번호>-<키워드>` 브랜치에서 작업해 마일스톤 브랜치로 squash 머지합니다.
- 마일스톤이 끝나면 PR을 Ready로 바꿔 전체 CI를 통과시킨 뒤 `main`에 merge 커밋으로 머지합니다.
- CI: 마일스톤 브랜치 대상 PR은 `Sub-issue Linux CI`(analyze·test·dev APK·설정 스키마 검증), `main` 대상 PR은 `Milestone Full Multi-Platform CI`(analyze·test·설정 스키마 검증, Android 3개 flavor, iOS no-codesign). 설정 스키마 검증은 로컬에서도 `bash tool/validate_config.sh`로 돌릴 수 있습니다(의존성: `tool/requirements-ci.txt`). iOS flavor별 bundle ID·앱 이름은 macOS에서 `bash tool/check_ios_flavors.sh`로 확인합니다

Claude Code에서는 `/open-ms <에픽번호>`, `/fix-issue <서브이슈번호>`, `/close-ms <에픽번호>`로 이 흐름을 실행합니다 (`.claude/skills/`).

M1은 이 규칙을 도입하기 전에 시작해 `step1/project-setup` 브랜치(PR #12)로 마무리하고, M2부터 위 규칙을 씁니다.

## 구성

```
config/      앱 설정 스키마와 flavor(dev/stg/prod)별 설정
docs/        단계별 설계·결정 문서
lib/         앱 코드
test/        Dart 테스트
test-page/   단계별 검증용 기능 테스트 HTML 페이지
android/ ios/
.claude/     Claude Code 프로젝트 스킬(/open-ms, /fix-issue, /close-ms)과 보드 스크립트
.github/     CI 워크플로
CLAUDE.md    프로젝트 규칙 (단일 기준)
milestone.md 마일스톤 체크리스트
```

## 개발 환경

- Flutter 3.50.0 (`.fvmrc`). fvm을 쓰면 `fvm use`로 맞춥니다.
- Android: JDK 17 이상, Android SDK platform 37
- iOS: Xcode. 플러그인은 Swift Package Manager로 연결되어 CocoaPods가 필요 없습니다 (#52)

## 실행

```sh
flutter pub get

# Android·iOS 모두 --flavor로 고른다 (iOS는 Xcode scheme dev/stg/prod)
flutter run --flavor dev
flutter build apk --release --flavor prod
flutter build ios --release --flavor prod
```

release 빌드는 flavor를 지정하지 않으면 시작하지 않습니다. iOS는 flavor 없는 scheme이 없어 `--flavor` 없이 빌드할 수 없습니다.

```sh
flutter analyze
flutter test
```

## 기능 테스트 페이지 띄우기

```sh
cd test-page
python -m http.server 8080
```

- 브라우저: `http://localhost:8080/`
- Android 에뮬레이터 앱: dev 설정의 `startUrl`을 `http://10.0.2.2:8080/`로 바꿉니다(dev는 `allowHttp: true`).
- 실기기: 같은 네트워크의 PC IP를 쓰고, 그 호스트를 `allowedHosts`에 추가합니다.
