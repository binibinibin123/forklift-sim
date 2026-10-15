# 지게차 실기 3D (forklift-sim)

지게차운전기능사 실기 코스를 3D로 재현해 코스 순서와 실격·감점 기준을 연습하는 iOS 앱. Godot 4.7.2 (Mobile), 가로 화면.

- 번들: com.yubinapps.forkliftsim, 표시 이름 "지게차 실기"
- 근거·범위: 11_조사_3D유료앱_2026-10-15.md

## 구조
- `data/course.json` 코스 치수(직사각형 합집합), 드럼·하역 표시·후진선 위치. **추정치**: 큐넷 공개문제 도면으로 확인 후 고칠 것.
- `scripts/sim.gd` 주행(뒷바퀴 조향)·포크·팔레트·채점. 화면과 무관한 순수 로직.
- `scripts/course.gd` 코스 데이터, 영역·경계선 계산
- `scripts/world.gd`, `scripts/forklift_view.gd` 코드로 만든 3D 모델
- `scripts/controls.gd` 멀티터치 조작부(핸들, 전후진·리프트·틸트 레버, 가속·브레이크 페달)
- `scripts/main.gd` 연습/모의시험, 결과, 리플레이, 카메라 4종(운전석·뒤·포크 옆·위)
- `tests/test_sim.gd` 헤드리스 테스트. 자동 운전(`tests/autopilot.gd`)으로 코스를 완주해 합격하는지 확인

## 실행
```
godot --headless --path . --script res://tests/test_sim.gd      # 테스트
godot --path . -- shot=out.png scene=cab stop=3                  # 스크린샷(menu|cab|chase|side|top|result)
```
키보드(데스크톱): W 가속, S 브레이크, A/D 핸들, 1/2/3 전진·중립·후진, R/F 리프트, T/G 틸트, B 안전벨트, P 주차브레이크, C 시점, Enter 시작 신호.

## 채점(1차)
실격: 안전벨트 없이 출발, 신호 후 1분 내 미출발, 4분 초과, 바퀴 선 접촉, 주행 중 포크 50cm 초과, 포크·화물 바닥 접촉, 드럼 접촉, 팔레트 밀어냄·낙하, 포크 20cm 넘게 덜 넣음, 하역 위치 20cm 초과, 팔레트 없이 작업구역 이탈, 후진선이 아닌 곳에 포크 닿음.
감점(각 5점): 주행 포크 높이 20~30cm 이탈, 화물 싣고 틸트 안 젖힘, 후진선 정지 후 중립 안 함, 완전히 서기 전 포크 내림.
감점 배점은 공개문제 확인 후 조정.

## 빌드
`github-workflows/ios-testflight.yml`을 저장소의 `.github/workflows/`로 옮겨 Actions에서 수동 실행(시크릿 ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8).
