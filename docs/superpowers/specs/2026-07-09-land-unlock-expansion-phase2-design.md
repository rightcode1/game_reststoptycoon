# 부지 해금 확장 — Phase 2 설계

**구역(플롯) 단위 · 인접 확장 · 점증 비용**

작성: 2026-07-09 · 브랜치: `claude/construction-traffic-gameplay-3e5390` · 선행: Phase 1(평판 루프) 완료

---

## 1. 배경 / 목표

현재 50×50 맵 전체가 처음부터 건설 가능하다. Phase 2는 **초기엔 작은 시작 부지만 열고, 나머지를 돈으로 해금**하는 성장축을 추가한다 — 정체 완화용 주차 부지 확보가 곧 돈 소비처가 되고, "확장하는 손맛"을 준다.

**핵심 통찰:** 잠금은 **건설만 게이트**한다. 차량/보행자 경로와 기본 주차 슬롯(2092/2121)에는 관여하지 않으므로, 잠긴 구역의 코리도로도 차가 다니고 게임이 정상 작동한다. **하드코딩 타일 번호를 안 건드린다.**

## 2. 스코프

**포함:** 플롯 모델, 배치 게이트(잠긴 땅 건설 불가), 탭-해금 상호작용+다이얼로그, 점증 비용, 잠긴 땅 렌더 구분, 저장 v7→v8.

**제외(후속):** 진입로·대기열 확장(Phase 3), 보행자 벽 문제.

## 3. 설계

### A. 플롯 모델

- `Balance.landPlotSize`(=10)로 50×50을 분할 → **5×5 = 25 플롯**.
- 타일의 플롯키: `plotKey(x, y) = ((x - 1) ~/ landPlotSize) * plotsPerRow + ((y - 1) ~/ landPlotSize)`,
  `plotsPerRow = mapColumns ~/ landPlotSize`(=5). px, py ∈ 0..4.
- 상태: `Set<int> _unlockedPlots`.
- **시작 해금 플롯:** 기능적 시작 영역을 덮는 플롯을 연다 — 초기 상업 타일 **2147**, 기본 주차 라벨 타일 **2092·2121**의 플롯. init에서 이 타일들의 `plotKey`를 계산해 `_unlockedPlots`에 넣는다(정확한 키는 런타임 계산, 스모크 테스트로 첫 매장·첫 주차 가능 보장). 도우미 `_startingUnlockedPlots()`.

### B. 배치 게이트

- `_placementFootprintFor`: 발자국 각 타일에 대해 `_isPlotUnlocked(tile)`가 false면 `null` 반환(건설 거부).
- 도우미:
  ```
  int _plotKeyForTile(MapTile t) =>
      ((t.logicalX - 1) ~/ Balance.landPlotSize) * _plotsPerRow
      + ((t.logicalY - 1) ~/ Balance.landPlotSize);
  bool _isPlotUnlocked(MapTile t) => _unlockedPlots.contains(_plotKeyForTile(t));
  ```
  (진입 도로 타일은 y ≥ entryRoadStartY라 기존 배치 규칙에서 이미 걸러지고, 플롯 계산에도 안전하게 포함되지 않도록 y 범위 확인.)

### C. 해금 상호작용

- `handleTap`에서: 배치 모드가 아니고, 탭이 해소된 타일이 **잠긴 플롯**이면:
  - 그 플롯이 **열린 플롯과 직교 인접**(상/하/좌/우)이면 → `landUnlockRequest` notifier에 `(plotKey, cost)` 발행 → UI 다이얼로그.
  - 인접이 아니면 → `notice`로 "인접한 구역만 해금할 수 있습니다".
- 기존 탭 라우팅(빈 상업 타일=아무 동작 없음, 매장 타일=업그레이드 요청)보다 **잠금 검사를 먼저** 둔다(잠긴 타일엔 매장이 없으므로 충돌 없음).
- 확정: UI가 `game.unlockPlot(plotKey)` 호출 → 비용 확인·차감, `_unlockedPlots.add`, 저장, `_bumpQuestStat(QuestMetric.landUnlocked)`(선택), `notice`.
- 인접 판정 도우미 `_isPlotAdjacentToUnlocked(plotKey)`: px±1/py±1 중 하나라도 `_unlockedPlots`에 있으면 true.

### D. 비용 (점증 · `balance.dart`)

- `landUnlockCost(unlockedBeyondStartCount) = landUnlockBaseCost * (unlockedBeyondStartCount + 1)`.
- 초안: `landUnlockBaseCost = 2000`. `unlockedBeyondStartCount = _unlockedPlots.length - 시작플롯수`.
- 전부 튜닝 상수. `test/balance_test.dart`에 정합성 케이스.

### E. 렌더 (가시성)

- 잠긴 플롯 타일은 **어둡게/탈채도**(반투명 어두운 오버레이)로 그려 열린 땅과 구분.
- 카메라 최근접 **해금 가능(인접) 플롯**에 자물쇠 + 가격 힌트 표시(간단 텍스트/아이콘). 없으면 생략 가능(최소 구현은 잠금 딤만).
- 카메라는 전체 맵 자유 이동 유지(잠긴 땅도 보임). 카메라 클램프 변경 없음.

### F. 저장 / 마이그레이션 (`save.dart` v7 → v8)

- `GameSaveData.unlockedPlots`(`List<int>?`, 기본 null) 추가, 버전 v8.
- 게임 `onLoad` 복원 규칙:
  - **저장 없음(완전 새 게임):** `_unlockedPlots = _startingUnlockedPlots()` — 잠금 메커닉 활성.
  - **v7 이하 저장(기존 유저):** `unlockedPlots`가 null → **전체 개방**(`_unlockedPlots = 모든 플롯키`). 기존 배치가 잠긴 땅에 갇히는 문제 회피(결정: 전체 개방).
  - **v8 저장:** 저장된 집합 복원.
- `reset()`(데이터 초기화) → `_startingUnlockedPlots()`.
- `_currentSaveData()`는 `unlockedPlots: _unlockedPlots.toList()` 저장.

### G. UI ↔ 게임 연결

- 신규 `ValueNotifier<LandUnlockRequest?> landUnlockRequest`(플롯키·비용). `app.dart`가 구독해 다이얼로그 표시, `dispose()`에 해제 추가.
- `LandUnlockRequest` 데이터 클래스(plotKey, cost).

### H. 퀘스트 (선택)

- `questLine` **맨 끝에만** "부지 N구역 해금" 1개 + `QuestMetric.landUnlocked`(enum 끝에 추가). 원치 않으면 생략.

## 4. 밸런스 훅 (`lib/core/balance.dart`)

| 상수 | 기본값(초안) | 의미 |
|---|---|---|
| `landPlotSize` | 10 | 플롯 한 변의 타일 수(50 나눔) |
| `landUnlockBaseCost` | 2000 | 첫 해금 비용(점증 기준) |
| `landUnlockCost(n)` | 함수 | `base * (n+1)`, n=시작분 제외 해금 수 |

## 5. 테스트

- **balance_test:** `landPlotSize`가 `mapColumns`를 나눔, 비용이 n에 비례·양수.
- **land_test(신규):**
  - 새 게임: 시작 플롯만 열림, 먼 플롯은 잠김.
  - 잠긴 플롯 타일엔 건설 거부, 열린 플롯엔 허용.
  - 인접 플롯 해금 시 비용 차감·`_unlockedPlots` 증가; 비인접 거부.
  - 점증 비용: 두 번째 해금이 첫 번째보다 비쌈.
  - 저장 v8 왕복; v7(unlockedPlots 없음) → 전체 개방 마이그레이션.
- **스모크(시뮬레이터, 메모리 지침 필수):** 새 게임에서 첫 매장·첫 주차가 시작 부지 안에서 되는지 + 잠긴 구역 탭→해금 다이얼로그→해금 후 그 땅에 건설되는지.

## 6. 열린 항목 / 결정 유보

- 구버전(v7) 저장 마이그레이션: **전체 개방(기본)** — 확정.
- 플롯 크기 10(25플롯) — 확장 페이스는 플레이 후 `landPlotSize`/비용으로 튜닝.
- 렌더 자물쇠+가격 힌트 포함 여부(기본 포함, 여유 없으면 딤만 — 스트레치).
- "부지 해금" 퀘스트 포함 여부(기본 생략).

## 7. 후속 (참고)

- **Phase 3 — 진입로·대기열 확장:** 하드코딩 큐 동적화(고위험). Phase 1에서 넣은 gridlock 완화([[traffic-gridlock-constraint]])와 함께, 이 코리도를 크게 손대므로 마지막에 격리.
