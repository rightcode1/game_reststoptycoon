# 정체 완화 루프 — Phase 1 설계

**평판 시스템 + 주차 확장 통합 + 정체 가시화**

작성: 2026-07-09 · 브랜치: `claude/construction-traffic-gameplay-3e5390`

---

## 1. 배경 / 문제

건설로 유입이 늘면 길·주차가 막혀 차량과 손님이 정체되는 현상을, **버그가 아니라 플레이어가 극복하는 게임요소**로 전환한다.

현재 코드에서 "막힘"의 실체:

- 매장을 지으면 `StoreSpec` 수요 보정치가 일일 유입을 늘린다(`_buildingModifierFor`). 그러나 동시 수용은 주차 슬롯뿐이라 필연적 병목이 생긴다.
- 슬롯이 없으면 좌/우 대기열(각 4칸, 하드코딩)로 가고, `queueGiveUpMinutes`(60분) 초과 시 포기 → `passingThrough`로 이탈. 대기열도 꽉 차면 곧장 `passingThrough`.
- **이탈 차량은 아무 신호 없이 조용히 사라진다(매출 0).** 플레이어는 손님을 잃었다는 사실도, 왜 잃었는지도 모른다 → "불공정한 실패"처럼 느껴진다.

**핵심 관찰:** 스폰되는 모든 차량은 먼저 주차를 시도한다(`_spawnVehicle`: 빈 슬롯 → 대기열 → 통과 순). 순수 "지나가는 교통"이 없으므로 **`passingThrough` = 100% 정체로 인한 이탈**로 해석할 수 있다. 이 신호를 그대로 평판·손실 지표로 쓴다.

## 2. 목표 (Phase 1)

> "정체가 아프다 → 주차를 확장해 푼다 → 평판이 회복되고 유입이 는다"

이 완전한 피드백 루프를 **최소 위험**으로 구현한다. 하드코딩된 타일 맵(대기열/경로 타일 번호)은 이번 Phase에서 건드리지 않는다.

## 3. 스코프

**포함:**
- 평판 시스템(0~100, 이벤트 기반 EMA)
- 평판 → 미래 유입 피드백(수요 계수)
- 정체/이탈 가시화 HUD(평판 배지, 오늘 놓친 손님, 이탈 플로팅)
- 주차 확장을 "정체의 정답"으로 통합

**제외(후속 Phase):**
- 부지(맵) 해금 확장 → **Phase 2**
- 진입로·대기열 확장 → **Phase 3**(고위험, 격리)
- 보행자 벽(뒤쪽 매장 접근 차단) 문제 → 별도 과제

## 4. 설계

### A. 평판 시스템

- 상태: `double _reputation` — 범위 0~100, 시작값 `Balance.reputationStart`(=70).
- 갱신은 **이벤트 기반 EMA**로 부드럽게. 헬퍼:
  ```
  void _nudgeReputation(double target, double step) {
    _reputation = (_reputation + (target - _reputation) * step).clamp(0, 100);
    reputation.value = _reputation; // HUD notifier 갱신
  }
  ```
- 이벤트 훅:
  - **served** — 차량이 `arriving → parked`로 전이할 때(`_updateVehicles`, 현재 ~line 1650) → `_nudgeReputation(100, Balance.reputationServedStep)`.
  - **lost** — 차량이 정체로 `passingThrough`가 되는 두 지점:
    1. `_trySpawnVehicle`의 throughRoute 폴백(슬롯·대기열 모두 없음, ~line 1617)
    2. `_promoteQueuedVehicles`의 대기열 포기(`queueGiveUpMinutes` 초과, ~line 2101)
    → `_nudgeReputation(0, Balance.reputationLostStep)`.
  - **불변식:** `reputationLostStep > reputationServedStep`. 이탈 한 대가 정상 서비스 한 대보다 평판을 더 크게 움직여, 정체가 실제로 아프게 느껴지도록 한다.
- 손실 카운터: `int _lostToday` — lost 이벤트마다 +1, 게임 날짜가 바뀌면(`_rebuildTrafficPlan`가 새 날 감지하는 지점) 0으로 리셋. HUD "오늘 놓친 손님 N대"에 사용.

### B. 평판 → 수요 피드백

- 계수 함수:
  ```
  demandFactor(rep) = demandFactorMin
      + (demandFactorMax - demandFactorMin) * (rep / 100)
  ```
  기본값 `demandFactorMin=0.5`, `demandFactorMax=1.2` → 평판 0이면 0.5×, 100이면 1.2×.
- **바닥 0.5**가 회복 불가 죽음의 나선을 막는다: 평판이 바닥이어도 유입의 절반은 유지되므로, 용량을 고치면 served 비율이 올라 평판이 스스로 회복된다(자기 교정 루프).
- 적용 지점: `_dailyDemandRange`가 반환하는 `(base + modifier)` 범위 전체에 `demandFactor(_reputation)`를 곱한다. (min·max 동시 스케일)

### C. 가시화 (HUD)

- 신규 `ValueNotifier` (game → UI):
  - `reputation`(`ValueNotifier<double>` 또는 표시용 `ValueNotifier<String>`) — 상단 HUD 배지. 기본 표시는 `0~100` 정수 + 색(높음 초록 / 낮음 빨강). 별점 표시는 구현 시 선택.
  - `congestionNotice`(`ValueNotifier<int>` = `_lostToday`) — 값 > 0이면 HUD에 "정체 · 오늘 놓친 손님 N대" 경고 배지.
- 이탈 차량 시각화: `passingThrough`로 전환된 차량이 화면을 빠져나가기 전 흐리게/붉게 렌더링하고, **"놓침"(또는 잃은 예상 매출)** 플로팅 텍스트를 띄운다 — 기존 `FloatingSaleText`(양수 "+N원" 플로팅) 패턴을 회색/음수 변형으로 재사용.
- `app.dart`: 새 notifier를 HUD 위젯에서 구독하고, `dispose()`의 notifier 해제 목록에 추가한다(누락 시 릭 — CLAUDE.md 규칙).

### D. 주차 확장 통합

- 엔진은 이미 `주차`(200원) 시설로 **동적 슬롯 확장**을 지원한다(`_createParkingSlotAt` → 분기점 2093에서 BFS 경로 생성). Phase 1은 이 기존 능력을 "정체의 정답"으로 명확히 연결하는 것이 핵심 — 추가 엔진 작업 없음.
- (선택 · 스트레치) **포장주차** 신규 시설: 일반 주차와 같은 슬롯이지만 점유 시간이 절반(`Balance.fastParkDurationMinutes`=60). 공간 대비 처리율을 높이는 대안 선택지.
  - 구현: 주차 슬롯에 `parkDurationMinutes` 필드 추가(기본 슬롯=120, 포장=60). `_updateVehicles`의 `parkUntilMinute` 계산이 슬롯 값을 참조.
  - 여유가 없으면 Phase 2로 미룰 수 있다. Phase 1의 필수 경로는 **일반 주차 확장**만으로 성립한다.

## 5. 밸런스 훅 (`lib/core/balance.dart`)

모두 튜닝 대상으로 `Balance`에 상수로 추가한다(게임 로직 하드코딩 금지 규칙):

| 상수 | 기본값(초안) | 의미 |
|---|---|---|
| `reputationStart` | 70 | 시작 평판 |
| `reputationServedStep` | 0.02 | 정상 서비스 시 EMA 이동 비율 |
| `reputationLostStep` | 0.06 | 이탈 시 EMA 이동 비율(> served) |
| `demandFactorMin` | 0.5 | 평판 0에서의 유입 배수(바닥) |
| `demandFactorMax` | 1.2 | 평판 100에서의 유입 배수 |
| `fastParkDurationMinutes` *(선택)* | 60 | 포장주차 점유 시간 |
| `facilityCosts['포장주차']` *(선택)* | 400 | 포장주차 건설비 |

`test/balance_test.dart`에 정합성 케이스 추가(경계값·존재 검증).

## 6. 저장 / 마이그레이션 (`lib/core/save.dart` v6 → v7)

- `GameSaveData`에 `reputation`(double) 필드 추가, 스키마 버전 v7.
- 하위 버전(v6 이하) 로드 시 `reputation` 기본값 70으로 마이그레이션.
- 포장주차(선택)를 넣는 경우: 신규 시설은 `_placedTiles`에 label로 이미 저장되므로 자동 영속. `_syncDynamicParkingSlots`가 포장주차도 슬롯으로 재등록하고 슬롯별 `parkDurationMinutes`를 복원하도록 확장.
- `_lostToday`는 세션 지표이므로 저장하지 않는다(재시작 시 0).

## 7. 테스트 계획

- **balance_test**: `demandFactor` 경계(rep 0 → 0.5, rep 100 → 1.2), 신규 상수 존재·정합.
- **게임 로직 유닛**:
  - served/lost 이벤트가 평판을 각각 올바른 방향으로 이동시킨다.
  - `demandFactor`가 `_dailyDemandRange` 결과에 반영된다.
  - `_lostToday`가 날짜 전환에 리셋된다.
- **시뮬레이터 스모크**(메모리 지침: 시뮬레이터 직접 검증 필수):
  유입 폭주 유도 → 이탈 발생 → 평판 하락·"놓친 손님" HUD 확인 → 주차 확장 → 평판·유입 회복 관찰. `/run-reststop-tycoon` 스킬 절차 사용.

## 8. 열린 항목 / 결정 유보(구현 시 확정)

- 평판 표시 형식: 0~100 배지(기본) vs 별점.
- 포장주차 회전율 티어를 Phase 1에 포함할지(기본 포함·스트레치, 여유 없으면 P2).
- 퀘스트: `questLine` **맨 끝에만** "평판 80 달성" 1개 추가 여부(기본 생략 — questIndex 규칙상 중간 삽입 금지).

## 9. 후속 Phase (참고 — 이번 스코프 아님)

- **Phase 2 — 부지(맵) 해금 확장:** 맵은 이미 50×50 전체가 존재하므로, 그리드를 키우지 않고 기존 땅에 **잠금/해금 오버레이**를 얹어 돈으로 넓힌다 → 타일 번호 안전.
- **Phase 3 — 진입로·대기열 확장:** 하드코딩된 고정 큐(`leftQueueTileNumbers`/`rightQueueTileNumbers`)와 경로를 동적 구조로 일반화 → 고위험, 루프 검증 후 마지막에 단독으로.
