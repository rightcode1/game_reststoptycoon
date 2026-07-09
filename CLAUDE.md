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
fvm flutter test           # 유닛 테스트 (test/ — 밸런스 정합성, 경제 로직)
fvm flutter test integration_test/smoke_test.dart -d <시뮬레이터UDID>  # 스모크 테스트
```

앱 실행·조작·스크린샷 절차는 `/run-reststop-tycoon` 스킬([.claude/skills/run-reststop-tycoon/SKILL.md](.claude/skills/run-reststop-tycoon/SKILL.md))에 검증된 명령으로 정리되어 있습니다.

## 아키텍처

소스는 `lib/` 아래 9개 파일이며, 역할이 명확히 나뉩니다.

- [lib/main.dart](lib/main.dart) — 진입점.
- [lib/app.dart](lib/app.dart) — **Flutter 위젯 레이어**. `GameWidget`을 감싸는 `GestureDetector`가 팬/줌/탭 제스처를 받아 게임 객체의 `panBy`/`zoomAt`/`handleTap`으로 전달합니다(Flame 입력 이벤트를 쓰지 않음). HUD(시간/자금 배지, 퀘스트 배너), 유입 일정 다이얼로그, 건설 화면(`ConstructionScreen`)도 여기에 있습니다.
- [lib/game/highway_tycoon_game.dart](lib/game/highway_tycoon_game.dart) — **게임 로직 전체**. `FlameGame`을 상속하지만 Flame 컴포넌트 시스템을 쓰지 않고 `render()`에서 Canvas에 직접 그립니다. 카메라(팬/줌/클램프)도 Flame 카메라가 아닌 수동 구현입니다.
- [lib/core/balance.dart](lib/core/balance.dart) — **밸런스 수치**. 시작 자금, 건설비, 판매가, 차량 수요, 주차/대기/방문 시간과 `RestaurantSpec`/`VehicleDemandRange` 데이터 클래스. 튜닝 대상 수치는 게임 코드에 하드코딩하지 말고 여기에 추가할 것.
- [lib/core/settings.dart](lib/core/settings.dart) — **기기 설정**(`SettingsRepository`). 사운드 토글 등 진행 저장과 별도 키에 저장 — '데이터 초기화'에도 유지된다.
- [lib/core/assets.dart](lib/core/assets.dart) — **에셋 경로 상수**. 모든 에셋 참조를 여기에 모아 실제 에셋 교체 시 한 곳만 갱신하면 되게 한다.
- [lib/core/sound.dart](lib/core/sound.dart) — **사운드 훅**. `GameSound` 이벤트 8종과 `SoundPlayer` 인터페이스. 기본 구현은 `SilentSoundPlayer`(무음 플레이스홀더 — 오디오 에셋 미보유). 게임 로직은 재생 지점에서 `_sound.play()`만 호출.
- [lib/core/quests.dart](lib/core/quests.dart) — **퀘스트 라인**. 순차 진행 목표(`questLine`)와 지표(`QuestMetric`). 게임이 건설/판매/고용/업그레이드 시점에 지표를 올리고, 달성 시 보상 지급 후 다음 퀘스트로 진행(`questLabel` HUD 배너). 항목은 끝에만 추가할 것(중간 삽입 시 저장된 questIndex가 어긋남).
- [lib/core/save.dart](lib/core/save.dart) — **저장/로드**. `GameSaveData`(JSON 스키마, 버전 필드 — 현재 v6: level·savedAtEpochMs·staffCount·questIndex/questStats·tutorialSeen, 하위 버전은 필드 기본값으로 마이그레이션)와 `SaveRepository`(shared_preferences). 영속화 대상은 돈·게임 시간·배치 시설(레벨 포함)뿐이고 차량/보행자는 재시작 시 리셋. 게임은 건설/업그레이드 직후·10초 주기·앱 백그라운드 전환 시 저장하고 `onLoad()`에서 복원하며, 저장 시각 기반으로 오프라인 수익을 정산(`_settleOfflineEarnings`, 최대 8시간 인정)한다. 손상된 저장은 새 게임으로 처리. 주의: `flutter run` 재설치는 시뮬레이터 데이터 컨테이너를 지우므로 개발 중 저장이 사라진 것처럼 보일 수 있음(재설치 없는 재시작에서는 정상 복원).

### UI ↔ 게임 연결 방식

- 게임 → UI: `ValueNotifier`들을 HUD/리스너가 구독 — `timeLabel`/`moneyLabel`(HUD 배지), `notice`(스낵바, UI가 소비 후 null로 되돌림), `pendingPlacementLabel`(배치 모드 → 하단 취소 버튼), `upgradeRequest`(매장 탭 → 업그레이드 다이얼로그), `offlineEarnings`(재접속 → 부재 중 수익 다이얼로그), `questLabel`(HUD 퀘스트 배너), `tutorialRequested`(최초 실행 → 튜토리얼 다이얼로그), `soundEnabled`(설정 스위치). (`app.dart`의 `dispose()`에서 전부 해제하므로 notifier를 추가하면 거기도 갱신 필요)
- UI → 게임: 건설 화면에서 아이템 이름(String)을 반환하면 `startPlacement()` → 맵 탭 시 `handleTap()`으로 배치.
- **매장 이름 문자열이 곧 키**: `ConstructionScreen.itemsByCategory`(app.dart)와 `Balance.restaurantSpecs`/`Balance.facilityCosts`(core/balance.dart)가 '라면', '국밥' 같은 한국어 문자열로 연결됩니다. 매장을 추가/이름 변경할 때 양쪽 파일을 모두 맞춰야 하며, `test/balance_test.dart`가 정합성을 검증합니다.

### 타일 맵과 좌표 체계

- 50×50 논리 그리드(`logicalX`/`logicalY`, 1부터 시작) + 진입 도로 타일. `_tileCenter()`가 논리 좌표를 아이소메트릭 월드 좌표(마름모 타일, 반폭 42/반높이 22)로 변환.
- 타일은 깊이 정렬 후 1부터 `tileNumber`가 부여되며(화면 표시는 디버그 빌드 전용 — 릴리즈에서는 숨김), **게임 로직 대부분이 하드코딩된 타일 번호로 동작**합니다: 주차 슬롯(2092, 2121), 대기열 타일, 화장실/나무/주차 라벨 타일, 차량 경로(`_routeForParkingSlot`, `_exitRouteFor`, `_throughRoute` 등)가 모두 타일 번호 리스트입니다. 맵 크기나 정렬을 바꾸면 이 번호들이 전부 어긋나므로 주의.
- 타일 존은 `TileZone.parking`(x ≤ 25)과 `TileZone.commercial`로 나뉘며, 주차 시설은 parking 존에만, 식당은 commercial 존에 세로 2타일로 배치됩니다. 배치 위치는 탭한 곳이 아니라 **카메라 중앙에서 가장 가까운 유효 타일**(회색으로 하이라이트)입니다.

### 시뮬레이션 루프 (`update()`)

- 게임 시간: 현실 1초 = 게임 분으로 환산(`gameMinutesPerRealSecond`), 1게임년 = 현실 129,600초. 모든 타이머(주차 시간, 대기열 승격, 방문 시간)는 게임 분 기준.
- 교통: 게임 날짜가 바뀔 때마다 `_rebuildTrafficPlan()`이 하루치 `DailyArrival` 스케줄을 생성. 차량 수요는 기본 범위 + 배치된 식당의 `RestaurantSpec` 수요 보정치(세단/트럭/버스별)의 합으로 결정됩니다 — 건물을 지을수록 유입이 늘어나는 핵심 경제 루프.
- 차량 상태 머신(`VehicleState`): 주차 슬롯이 비면 arriving → parked(120게임분) → exiting. 슬롯이 없으면 좌/우 대기열(queueing)에 진입하고, 60게임분 초과 대기 시 passingThrough로 이탈. 대기열 앞차는 슬롯이 비면 승격(`_promoteQueuedVehicles`).
- 주차 슬롯: 기본 2개(2092, 2121)는 하드코딩 경로를 쓰고, '주차' 시설을 배치하면 동적 슬롯이 등록된다. 동적 슬롯의 진입/승격/출차 경로는 분기점(2093)·출차 합류점(2033) 기준 BFS(`_vehicleTilePathBetween`)로 생성. 도로/대기열 타일(`vehicleCorridorTileNumbers`)과 진입 도로에는 주차 배치 불가, 진입 경로가 없는 위치는 배치 거부. 저장 복원 시 `_syncDynamicParkingSlots()`가 슬롯을 재등록한다.
- 보행자: 차량이 주차되면 승객을 스폰. 도달 가능한 매장 목록(`_reachableStorePlans`)에서 **승객마다 차량 유형별 수요 가중치로 매장을 선택**(`_pickWeightedStorePlan` — 트럭은 백반, 버스는 호두과자 선호 등)해 매장 앞 타일까지 BFS 이동, 매장이 없으면 가장 가까운 빈 상업 타일로 산책. outbound → dwell → returning이며, **매장 도착 시점에 레벨·직원 보너스가 반영된 판매가만큼 매출 발생**(`_recordSaleAt`) + "+N원" 플로팅 텍스트 표시. 차량이 떠나면 해당 보행자도 제거됩니다.

### 기타 참고

- `assets/images/`의 차량 스프라이트는 pubspec에 등록되어 있지만 아직 코드에서 사용하지 않습니다. 차량/보행자는 색상 도형으로 렌더링됩니다.
- `assets/reference/concept.png`는 아트 콘셉트 참고 이미지입니다.
