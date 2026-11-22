# 개발 마일스톤 (Development Milestones)

> 각 마일스톤은 GitHub 마일스톤·에픽 이슈(`[M<N>]`)와 1:1로 대응한다. 원본 단계표: [docs/phase-0-requirements.md](docs/phase-0-requirements.md)

## [ ] M1: 프로젝트 셋업
- [x] 패키지 버전 고정
- [x] 번들 ID
- [x] minSdk/iOS 버전
- [x] Manifest·Info.plist 권한 문구
- [x] 기본 스킴용 Android `<queries>`
- [x] FileProvider
- 완료 기준: 빈 앱이 양쪽 실기기에서 실행

## [ ] M2: 웹뷰 코어 (`AppWebView`)
- [ ] 기본 설정(DOM storage, 쿠키, 서드파티 쿠키, UA, 디버깅)
- [ ] 도메인 정책
- [ ] URL 오버라이드 골격
- [ ] 기본 앱 스킴(tel/sms/mailto/geo) 실행
- 완료 기준: 로그인 후 앱 재시작해도 세션 유지, tel/sms/mailto 링크로 기본 앱 실행

## [ ] M3: JS 브릿지 기반
- [ ] `App.*` 네임스페이스
- [ ] `appready` 이벤트
- [ ] document-start 주입
- [ ] 메시지 규약
- 완료 기준: 웹→앱→웹 왕복 호출 통과

## [ ] M4: 스플래시
- [ ] `flutter_native_splash`
- [ ] Stack 오버레이
- [ ] 닫힘 조건 4종
- [ ] 타임아웃
- 완료 기준: 콜드스타트 깜빡임 없이 설정대로 닫힘

## [ ] M5: 시스템 UI·테마
- [ ] 상태바/네비바 모드
- [ ] Safe area CSS 변수 주입
- [ ] 테마 웹 전달
- [ ] 런타임 변경 API
- 완료 기준: 노치·제스처바 기기, Android 15+, 다크모드 전환 검증

## [ ] M6: 다이얼로그
- [ ] Alert/Confirm/Prompt/beforeunload
- [ ] 앱 이름 제목
- [ ] 결과 반환
- 완료 기준: 테스트 페이지 4종 통과

## [ ] M7: 팝업 윈도우
- [ ] onCreateWindow → PopupScreen 재귀
- [ ] onCloseWindow
- [ ] opener/postMessage 검증
- [ ] 브릿지 결과 전달
- [ ] 뒤로가기 연동
- [ ] maxDepth
- 완료 기준: 팝업→팝업→결과 전달→순차 닫힘

## [ ] M8: 파일 업로드
- [ ] accept/multiple/capture 해석
- [ ] 권한
- [ ] Android FileProvider
- 완료 기준: 이미지·동영상·PDF, 다중 선택 업로드

## [ ] M9: 위치
- [ ] geolocation 폴리필
- [ ] 권한 흐름
- [ ] watchPosition
- [ ] 에러 코드 호환
- 완료 기준: 허용/거부/영구 거부 시나리오 처리

## [ ] M10: 다운로드·공유·클립보드·인쇄
- [ ] 일반/blob/data 다운로드
- [ ] share·clipboard 폴리필
- [ ] print
- 완료 기준: 테스트 페이지 통과

## [ ] M11: 미디어
- [ ] 동영상 전체화면
- [ ] 인라인 재생
- [ ] getUserMedia 권한
- 완료 기준: 유튜브 임베드 전체화면, WebRTC(필요 시)

## [ ] M12: 안정성·네트워크
- [ ] 에러/오프라인 페이지
- [ ] 재시도
- [ ] 렌더 프로세스 복구
- [ ] 쿠키 flush
- [ ] 라이프사이클 이벤트
- 완료 기준: 비행기 모드, 장시간 백그라운드 후 복귀

## [ ] M13: 부가 기능
- [ ] FCM/APNs
- [ ] 토큰 웹 전달
- [ ] 알림 탭 → URL 이동
- [ ] App/Universal Link
- [ ] 강제 업데이트
- 완료 기준: 푸시 수신 → 해당 페이지 진입

## [ ] M14: 통합 테스트
- [ ] Android 9~16 / iOS 16~최신
- [ ] 저사양·태블릿
- [ ] Android WebView 140 미만 포함
- 완료 기준: 체크리스트 전부 통과

## [ ] M15: 출시 준비
- [ ] 권한 사용 문구
- [ ] iOS Privacy Manifest
- [ ] Play 타깃 SDK 요건
- [ ] 아이콘·스크린샷
- 완료 기준: 양쪽 심사 통과
