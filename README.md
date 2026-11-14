# u4-client

`flutter_inappwebview` 기반 웹 하이브리드 앱 클라이언트입니다. 웹 코드는 브라우저 표준 그대로 두고, 네이티브 연동은 웹뷰 콜백과 표준 웹 API 폴리필로 처리합니다.

## 진행 상황

| 단계 | 작업 | 문서 |
|---|---|---|
| 0 | 요구사항·설정 스키마 확정 | [docs/phase-0-requirements.md](docs/phase-0-requirements.md) |
| 1 | 프로젝트 셋업 | [docs/phase-1-setup.md](docs/phase-1-setup.md) |

2단계 이후 작업은 GitHub 마일스톤으로 관리합니다.

## 구성

```
config/      앱 설정 스키마와 flavor(dev/stg/prod)별 설정
docs/        단계별 설계·결정 문서
lib/         앱 코드
test/        Dart 테스트
test-page/   단계별 검증용 기능 테스트 HTML 페이지
android/ ios/
```

## 개발 환경

- Flutter 3.50.0 (`.fvmrc`). fvm을 쓰면 `fvm use`로 맞춥니다.
- Android: JDK 17 이상, Android SDK platform 37
- iOS: Xcode, CocoaPods (SwiftPM을 지원하지 않는 플러그인용)

## 실행

```sh
flutter pub get

# Android: --flavor로 고른다
flutter run --flavor dev
flutter build apk --release --flavor prod

# iOS: Xcode flavor가 아직 없어 dart-define으로 고른다 (docs/phase-1-setup.md 2장)
flutter run --dart-define=FLAVOR=dev
flutter build ios --release --dart-define=FLAVOR=prod
```

release 빌드는 flavor를 지정하지 않으면 시작하지 않습니다.

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
