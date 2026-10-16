# 지게차 실기 3D — 앱인토스(토스 미니앱) 버전

Godot 웹 빌드(`../export_presets.cfg`의 "Web" 프리셋, 스레드 없음·호환 렌더러)를
앱인토스 WebView SDK(`@apps-in-toss/web-framework` 3.x)로 감싼 것.

## 빌드
```
npm install
GODOT=/path/to/Godot_v4.7.2 npm run godot   # public/game 에 웹 빌드 + config.json
npm run build                               # dist/ + forklift-sim.ait
```
`npm run dev` 로 로컬 확인(토스 밖에서는 결제·화면 방향 API가 실패하고, 잠긴 상태로 열림).

## 구성
- `index.html`, `src/main.js`: 가로 화면 전환(`Screen.setOrientation`), Godot 엔진 시작, 로딩 막대.
- `src/bridge.js`: `window.aitBridge` — Godot `scripts/iap.gd` 가 부르는 결제 다리.
  - 비소모성 상품 SKU: `forkliftsim_unlock` (콘솔 등록값과 같아야 함)
  - 시작할 때 미지급 주문 지급 처리 → 완료/환불 기록으로 보유 여부 확인(기기 바꿔도 유지).
- `apps-in-toss.config.ts`: appName `forklift-sim` (콘솔 값과 같아야 함).

## 토스 버전 차이
- 지원·개인정보 바깥 링크 숨김(커스텀 기능 `toss`). 바깥 사이트 이동 금지 규칙.
- 메뉴에 소리 켜기/끄기, 앱이 뒤로 가면 소리 음소거.
- 호환 렌더러에서 바닥이 하얗게 떠서 바닥만 조명 없이 그림.

## 콘솔에서 할 일
1. 앱인토스 콘솔에 미니앱 생성(appName `forklift-sim`, 게임 아님/교육, 가로 화면).
2. 인앱결제 상품: 비소모성, SKU `forkliftsim_unlock`, ₩5,500, 이름 "전체 해제".
3. `forklift-sim.ait` 업로드 → 토스 앱 QR 테스트 → 검수 요청.
