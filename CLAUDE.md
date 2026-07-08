# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

한국 고속도로 휴게소 경영 타이쿤 프로토타입. Flutter + Flame(^1.19.0) 기반이며, 모든 UI 텍스트와 게임 데이터(매장 이름 등)는 한국어입니다. 세로(portrait) 전용 모바일 게임입니다.

## 개발 명령어

Flutter 버전은 FVM으로 3.32.6에 고정되어 있고, 이 환경에는 `flutter`가 PATH에 없으므로 반드시 `fvm flutter`를 사용해야 합니다.

```bash
fvm flutter pub get        # 의존성 설치
fvm flutter run            # 앱 실행 (기기/시뮬레이터 필요)
fvm flutter analyze        # 정적 분석 (린트: flutter_lints 기본 규칙)
fvm flutter test integration_test/smoke_test.dart -d <시뮬레이터UDID>  # 스모크 테스트 (유닛 테스트는 없음)
```

앱 실행·조작·스크린샷 절차는 `/run-reststop-tycoon` 스킬([.claude/skills/run-reststop-tycoon/SKILL.md](.claude/skills/run-reststop-tycoon/SKILL.md))에 검증된 명령으로 정리되어 있습니다.

## 아키텍처

소스는 `lib/` 아래 3개 파일뿐이며, 역할이 명확히 나뉩니다.

- [lib/main.dart](lib/main.dart) — 진입점.
- [lib/app.dart](lib/app.dart) — **Flutter 위젯 레이어**. `GameWidget`을 감싸는 `GestureDetector`가 팬/줌/탭 제스처를 받아 게임 객체의 `panBy`/`zoomAt`/`handleTap`으로 전달합니다(Flame 입력 이벤트를 쓰지 않음). HUD(시간/매출 배지), 유입 일정 다이얼로그, 건설 화면(`ConstructionScreen`)도 여기에 있습니다.
- [lib/game/highway_tycoon_game.dart](lib/game/highway_tycoon_game.dart) — **게임 로직 전체**. `FlameGame`을 상속하지만 Flame 컴포넌트 시스템을 쓰지 않고 `render()`에서 Canvas에 직접 그립니다. 카메라(팬/줌/클램프)도 Flame 카메라가 아닌 수동 구현입니다.

### UI ↔ 게임 연결 방식

- 게임 → UI: `ValueNotifier<String>`인 `timeLabel`/`moneyLabel`을 HUD가 구독. (`app.dart`의 `dispose()`에서 해제하므로 notifier를 추가하면 거기도 갱신 필요)
- UI → 게임: 건설 화면에서 아이템 이름(String)을 반환하면 `startPlacement()` → 맵 탭 시 `handleTap()`으로 배치.
- **매장 이름 문자열이 곧 키**: `ConstructionScreen`의 `_itemsByCategory`와 게임의 `buildCosts`/`restaurantSpecs`가 '라면', '국밥' 같은 한국어 문자열로 연결됩니다. 매장을 추가/이름 변경할 때 양쪽 파일을 모두 맞춰야 합니다.

### 타일 맵과 좌표 체계

- 50×50 논리 그리드(`logicalX`/`logicalY`, 1부터 시작) + 진입 도로 타일. `_tileCenter()`가 논리 좌표를 아이소메트릭 월드 좌표(마름모 타일, 반폭 42/반높이 22)로 변환.
- 타일은 깊이 정렬 후 1부터 `tileNumber`가 부여되며, **게임 로직 대부분이 하드코딩된 타일 번호로 동작**합니다: 주차 슬롯(2092, 2121), 대기열 타일, 화장실/나무/주차 라벨 타일, 차량 경로(`_routeForParkingSlot`, `_exitRouteFor`, `_throughRoute` 등)가 모두 타일 번호 리스트입니다. 맵 크기나 정렬을 바꾸면 이 번호들이 전부 어긋나므로 주의.
- 타일 존은 `TileZone.parking`(x ≤ 25)과 `TileZone.commercial`로 나뉘며, 주차 시설은 parking 존에만, 식당은 commercial 존에 세로 2타일로 배치됩니다. 배치 위치는 탭한 곳이 아니라 **카메라 중앙에서 가장 가까운 유효 타일**(회색으로 하이라이트)입니다.

### 시뮬레이션 루프 (`update()`)

- 게임 시간: 현실 1초 = 게임 분으로 환산(`gameMinutesPerRealSecond`), 1게임년 = 현실 129,600초. 모든 타이머(주차 시간, 대기열 승격, 방문 시간)는 게임 분 기준.
- 교통: 게임 날짜가 바뀔 때마다 `_rebuildTrafficPlan()`이 하루치 `DailyArrival` 스케줄을 생성. 차량 수요는 기본 범위 + 배치된 식당의 `RestaurantSpec` 수요 보정치(세단/트럭/버스별)의 합으로 결정됩니다 — 건물을 지을수록 유입이 늘어나는 핵심 경제 루프.
- 차량 상태 머신(`VehicleState`): 주차 슬롯이 비면 arriving → parked(120게임분) → exiting. 슬롯이 없으면 좌/우 대기열(queueing)에 진입하고, 60게임분 초과 대기 시 passingThrough로 이탈. 대기열 앞차는 슬롯이 비면 승격(`_promoteQueuedVehicles`).
- 보행자: 차량이 주차되면 승객을 스폰하고, BFS(`_findPedestrianRouteToCommercial`)로 주차 존을 거쳐 상업 타일까지 경로 탐색 → outbound → dwell → returning. 차량이 떠나면 해당 보행자도 제거됩니다.

### 기타 참고

- `assets/images/`의 차량 스프라이트는 pubspec에 등록되어 있지만 아직 코드에서 사용하지 않습니다. 차량/보행자는 색상 도형으로 렌더링됩니다.
- `assets/reference/concept.png`는 아트 콘셉트 참고 이미지입니다.
