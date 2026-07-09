# 정체 완화 루프 Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 정체로 이탈하는 차량을 평판 지표로 연결해, "정체가 아프다 → 주차를 확장해 푼다 → 평판·유입이 회복된다"는 피드백 루프를 만든다.

**Architecture:** 평판(0~100)을 이벤트 기반 EMA로 갱신(정상 주차=상승, 정체 이탈=하락). 평판은 `Balance.demandFactor`(0.5~1.2, 바닥 0.5로 죽음의 나선 방지)를 통해 다음 날 유입에 반영된다. HUD가 평판·"오늘 놓친 손님"을 표시하고, 이탈 차량엔 "놓침" 플로팅을 띄운다. 하드코딩된 대기열/맵 타일은 건드리지 않는다(그 확장은 Phase 2/3).

**Tech Stack:** Flutter + Flame(수동 Canvas 렌더). 상태는 `HighwayTycoonGame`(FlameGame), UI는 `ValueNotifier`로 연결. 저장은 shared_preferences(JSON). 테스트는 flutter_test.

**참고 스펙:** [2026-07-09-traffic-congestion-relief-phase1-design.md](../specs/2026-07-09-traffic-congestion-relief-phase1-design.md)

---

## 파일 구조

- `lib/core/balance.dart` — 평판/수요 상수 + `demandFactor()` 순수 함수(테스트 용이).
- `lib/game/highway_tycoon_game.dart` — 평판 상태·EMA·served/lost 훅·`_lostToday`·notifier·`_dailyDemandRange` 반영·이탈 플로팅.
- `lib/core/save.dart` — `GameSaveData`에 `reputation` 추가, v6→v7.
- `lib/app.dart` — 평판 배지·정체 경고 HUD, notifier dispose.
- `test/balance_test.dart` — 상수·`demandFactor` 경계.
- `test/reputation_test.dart` *(신규)* — served/lost 방향, `_lostToday`, demandFactor 반영, 이탈 플로팅.
- `test/save_test.dart` — reputation 왕복·마이그레이션.

**스코프 결정:** 포장주차(회전율 티어)는 이번 계획에서 **제외**(Phase 2로 이관). Phase 1 완화 레버는 기존 `주차` 시설로 충분하며, 루프 검증 전에 `ParkingSlot`/저장 표면을 늘리지 않는다(YAGNI).

---

## Task 1: 평판·수요 밸런스 상수와 `demandFactor`

**Files:**
- Modify: `lib/core/balance.dart`
- Test: `test/balance_test.dart`

- [ ] **Step 1: 실패하는 테스트 추가**

`test/balance_test.dart`의 `main()` 안, 마지막 `});`(group 닫힘, 82행 부근) 앞에 아래 그룹을 추가한다.

```dart
    test('평판·수요 밸런스 수치가 유효하다', () {
      expect(Balance.reputationStart, inInclusiveRange(0, 100));
      // 이탈이 정상 서비스보다 평판을 더 크게 움직여야 정체가 아프게 느껴진다.
      expect(
        Balance.reputationLostStep,
        greaterThan(Balance.reputationServedStep),
      );
      expect(Balance.reputationServedStep, greaterThan(0));
      expect(Balance.demandFactorMin, greaterThan(0));
      expect(
        Balance.demandFactorMax,
        greaterThan(Balance.demandFactorMin),
      );
    });

    test('demandFactor는 평판에 비례하며 바닥/천장을 지킨다', () {
      expect(Balance.demandFactor(0), closeTo(Balance.demandFactorMin, 1e-9));
      expect(Balance.demandFactor(100), closeTo(Balance.demandFactorMax, 1e-9));
      // 중간값은 선형 보간.
      expect(
        Balance.demandFactor(50),
        closeTo((Balance.demandFactorMin + Balance.demandFactorMax) / 2, 1e-9),
      );
      // 범위를 벗어난 입력도 클램프된다.
      expect(Balance.demandFactor(-20), closeTo(Balance.demandFactorMin, 1e-9));
      expect(Balance.demandFactor(200), closeTo(Balance.demandFactorMax, 1e-9));
    });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `fvm flutter test test/balance_test.dart`
Expected: FAIL — `Balance.reputationStart` 등 미정의로 컴파일 에러.

- [ ] **Step 3: 상수와 함수 구현**

`lib/core/balance.dart`의 `abstract final class Balance {` 안(예: `queueGiveUpMinutes` 정의 아래, 45행 부근)에 추가한다.

```dart
  /// 시작 평판(0~100).
  static const double reputationStart = 70;

  /// 차량이 정상 주차(서비스)될 때 평판이 100 쪽으로 이동하는 EMA 비율.
  static const double reputationServedStep = 0.02;

  /// 차량이 정체로 이탈할 때 평판이 0 쪽으로 이동하는 EMA 비율(> served).
  static const double reputationLostStep = 0.06;

  /// 평판 0에서의 유입 배수(바닥 — 죽음의 나선 방지).
  static const double demandFactorMin = 0.5;

  /// 평판 100에서의 유입 배수(천장 — 보너스).
  static const double demandFactorMax = 1.2;

  /// 평판(0~100)을 일일 유입 배수로 변환. 범위 밖 입력은 클램프한다.
  static double demandFactor(double reputation) {
    final clamped = reputation.clamp(0.0, 100.0);
    return demandFactorMin +
        (demandFactorMax - demandFactorMin) * (clamped / 100);
  }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `fvm flutter test test/balance_test.dart`
Expected: PASS (전체 그룹 통과).

- [ ] **Step 5: 커밋**

```bash
git add lib/core/balance.dart test/balance_test.dart
git commit -m "feat(balance): 평판·수요 상수와 demandFactor 추가"
```

---

## Task 2: 평판 상태·EMA·served/lost 훅·손실 카운터

**Files:**
- Modify: `lib/game/highway_tycoon_game.dart`
- Modify: `lib/app.dart` (신규 notifier dispose)
- Test: `test/reputation_test.dart` (신규)

- [ ] **Step 1: 실패하는 테스트 작성**

`test/reputation_test.dart` 생성:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HighwayTycoonGame> createGame() async {
    SharedPreferences.setMockInitialValues({});
    final game = HighwayTycoonGame();
    await game.onLoad();
    return game;
  }

  group('평판 시스템', () {
    test('새 게임 평판은 시작값이다', () async {
      final game = await createGame();
      expect(game.debugReputation, Balance.reputationStart);
    });

    test('정상 서비스는 평판을 올리고, 이탈은 내린다', () async {
      final game = await createGame();
      game.debugReputation = 50;

      game.debugRegisterServedVehicle();
      expect(game.debugReputation, greaterThan(50));

      game.debugReputation = 50;
      game.debugRegisterLostVehicle();
      expect(game.debugReputation, lessThan(50));
    });

    test('이탈이 정상 서비스보다 평판을 더 크게 움직인다', () async {
      final game = await createGame();

      game.debugReputation = 50;
      game.debugRegisterServedVehicle();
      final up = (game.debugReputation - 50).abs();

      game.debugReputation = 50;
      game.debugRegisterLostVehicle();
      final down = (50 - game.debugReputation).abs();

      expect(down, greaterThan(up));
    });

    test('평판은 0~100으로 클램프된다', () async {
      final game = await createGame();
      game.debugReputation = 100;
      game.debugRegisterServedVehicle();
      expect(game.debugReputation, lessThanOrEqualTo(100));

      game.debugReputation = 0;
      game.debugRegisterLostVehicle();
      expect(game.debugReputation, greaterThanOrEqualTo(0));
    });

    test('이탈은 오늘 놓친 손님 수를 늘린다', () async {
      final game = await createGame();
      expect(game.debugLostToday, 0);
      game.debugRegisterLostVehicle();
      game.debugRegisterLostVehicle();
      expect(game.debugLostToday, 2);
    });
  });
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `fvm flutter test test/reputation_test.dart`
Expected: FAIL — `debugReputation` 등 미정의 컴파일 에러.

- [ ] **Step 3: notifier·상태 필드 선언**

`lib/game/highway_tycoon_game.dart`에서 `questLabel` notifier 선언(113행 부근) 아래에 추가한다.

```dart
  /// 평판(0~100) — HUD 배지가 구독.
  final ValueNotifier<double> reputation =
      ValueNotifier<double>(Balance.reputationStart);

  /// 오늘 정체로 놓친 손님(차량) 수 — HUD 정체 경고가 구독.
  final ValueNotifier<int> congestion = ValueNotifier<int>(0);
```

`_currentTrafficDay` 필드(157행 부근) 아래에 상태 필드를 추가한다.

```dart
  double _reputation = Balance.reputationStart;
  int _lostToday = 0;
```

- [ ] **Step 4: EMA·register 메서드 구현**

같은 파일에서 `_bumpQuestStat` 메서드(226행 부근) **위**에 추가한다.

```dart
  /// 평판을 [target](0 또는 100) 쪽으로 [step] 비율만큼 EMA 이동.
  void _nudgeReputation(double target, double step) {
    _reputation = (_reputation + (target - _reputation) * step).clamp(0.0, 100.0);
    reputation.value = _reputation;
  }

  /// 차량이 정상 주차(서비스)됐을 때 호출 — 평판 상승.
  void _registerServedVehicle() {
    _nudgeReputation(100, Balance.reputationServedStep);
  }

  /// 차량이 정체로 이탈했을 때 호출 — 평판 하락 + 손실 카운터.
  /// [position]은 이탈 플로팅 표시에 쓰인다(Task 5에서 사용).
  void _registerLostVehicle(Offset position) {
    _nudgeReputation(0, Balance.reputationLostStep);
    _lostToday++;
    congestion.value = _lostToday;
  }
```

- [ ] **Step 5: served/lost 이벤트 훅 연결**

(a) **served** — `_updateVehicles`에서 arriving→parked 전이 지점. `vehicle.state = VehicleState.parked;`로 시작하는 블록(1650행 부근)에서 `_spawnPeopleForVehicle(vehicle);` 바로 다음 줄에 추가:

```dart
          _registerServedVehicle();
```

(b) **lost — 수용 초과 통과** — `_spawnVehicle`의 throughRoute 폴백에서 `passingThrough` 차량을 `_vehicles.add(...)` 하기 직전(1617행 부근, `final throughRoute = _throughRoute();`와 spawn occupied 체크 뒤)에 추가:

```dart
    _registerLostVehicle(throughRoute.first);
```

(c) **lost — 대기열 포기** — `_promoteQueuedVehicles`에서 give-up 처리(2101행 부근), `vehicle.state = VehicleState.passingThrough;` 다음 줄에 추가:

```dart
        _registerLostVehicle(vehicle.position);
```

- [ ] **Step 6: 날짜 전환 시 `_lostToday` 리셋**

`_rebuildTrafficPlan`에서 새 날 감지 후 `_currentTrafficDay = day;`(1450행 부근) 다음 줄에 추가:

```dart
    _lostToday = 0;
    congestion.value = 0;
```

- [ ] **Step 7: reset()에서 평판 초기화**

`resetProgress`/데이터 초기화 경로(`_currentTrafficDay = -1;`, 210행 부근) 다음 줄에 추가:

```dart
    _reputation = Balance.reputationStart;
    reputation.value = _reputation;
    _lostToday = 0;
    congestion.value = 0;
```

- [ ] **Step 8: 디버그 접근자 추가**

`debugFloatingSaleTextCount` getter(896행 부근) 근처, `@visibleForTesting` 블록에 추가한다.

```dart
  @visibleForTesting
  double get debugReputation => _reputation;

  @visibleForTesting
  set debugReputation(double value) {
    _reputation = value;
    reputation.value = value;
  }

  @visibleForTesting
  int get debugLostToday => _lostToday;

  @visibleForTesting
  void debugRegisterServedVehicle() => _registerServedVehicle();

  @visibleForTesting
  void debugRegisterLostVehicle() => _registerLostVehicle(Offset.zero);
```

- [ ] **Step 9: app.dart dispose에 notifier 해제 추가**

`lib/app.dart`의 `dispose()`에서 `_game.questLabel.dispose();`(52행 부근) 다음 줄에 추가:

```dart
    _game.reputation.dispose();
    _game.congestion.dispose();
```

- [ ] **Step 10: 테스트 통과 확인**

Run: `fvm flutter test test/reputation_test.dart`
Expected: PASS (5개 테스트).

- [ ] **Step 11: 커밋**

```bash
git add lib/game/highway_tycoon_game.dart lib/app.dart test/reputation_test.dart
git commit -m "feat(game): 평판 EMA + served/lost 훅 + 손실 카운터"
```

---

## Task 3: 평판을 일일 유입에 반영

**Files:**
- Modify: `lib/game/highway_tycoon_game.dart`
- Test: `test/reputation_test.dart`

- [ ] **Step 1: 실패하는 테스트 추가**

`test/reputation_test.dart`의 `group('평판 시스템', () {` 안 마지막에 추가한다.

```dart
    test('평판이 높을수록 일일 유입 범위가 커진다', () async {
      final game = await createGame();

      game.debugReputation = 100;
      final high = game.debugDailyDemandRange(VehicleType.sedan);

      game.debugReputation = 0;
      final low = game.debugDailyDemandRange(VehicleType.sedan);

      expect(high.max, greaterThan(low.max));
      // 매장이 없을 때 세단 기본 min은 12 → 평판 100이면 12×1.2.
      expect(
        high.min,
        closeTo(Balance.sedanDailyBase.min * Balance.demandFactorMax, 1e-6),
      );
      expect(
        low.min,
        closeTo(Balance.sedanDailyBase.min * Balance.demandFactorMin, 1e-6),
      );
    });
```

- [ ] **Step 2: 디버그 접근자 추가 후 실패 확인**

`lib/game/highway_tycoon_game.dart`의 `@visibleForTesting` 블록(Task 2 Step 8 근처)에 추가:

```dart
  @visibleForTesting
  VehicleDemandRange debugDailyDemandRange(VehicleType type) =>
      _dailyDemandRange(type);
```

Run: `fvm flutter test test/reputation_test.dart`
Expected: FAIL — `_dailyDemandRange`가 아직 평판을 곱하지 않아 high/low가 동일.

- [ ] **Step 3: `_dailyDemandRange`에 demandFactor 적용**

`_dailyDemandRange`(1485행 부근)의 `return VehicleDemandRange(...)`를 아래로 교체한다.

```dart
    final factor = Balance.demandFactor(_reputation);
    return VehicleDemandRange(
      min: (base.min + modifier.min) * factor,
      max: (base.max + modifier.max) * factor,
    );
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `fvm flutter test test/reputation_test.dart`
Expected: PASS.

- [ ] **Step 5: 회귀 확인**

Run: `fvm flutter test`
Expected: PASS (economy/parking 등 기존 테스트가 평판 70 기준 유입 변화에도 통과. 실패 시 해당 테스트가 절대 유입 수치에 의존하는지 확인 — 필요 시 그 테스트에서 `debugReputation`을 100으로 고정).

- [ ] **Step 6: 커밋**

```bash
git add lib/game/highway_tycoon_game.dart test/reputation_test.dart
git commit -m "feat(game): 평판을 일일 유입(demandFactor)에 반영"
```

---

## Task 4: 평판 저장/복원 (v6 → v7)

**Files:**
- Modify: `lib/core/save.dart`
- Modify: `lib/game/highway_tycoon_game.dart`
- Test: `test/save_test.dart`

- [ ] **Step 1: 실패하는 테스트 추가**

`test/save_test.dart`의 `group('GameSaveData 직렬화', () {` 안에 추가한다.

```dart
    test('reputation 왕복이 값을 보존한다', () {
      const original = GameSaveData(
        money: 100,
        elapsedGameMinutes: 0,
        placedTiles: [],
        reputation: 42.5,
      );
      final restored = GameSaveData.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.reputation, 42.5);
    });

    test('reputation 없는 구버전 저장은 기본값으로 마이그레이션된다', () {
      final restored = GameSaveData.fromJson({
        'version': 6,
        'money': 100,
        'elapsedGameMinutes': 0.0,
        'placedTiles': <dynamic>[],
      });
      expect(restored.reputation, GameSaveData.defaultReputation);
    });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `fvm flutter test test/save_test.dart`
Expected: FAIL — `reputation` 파라미터/필드 미정의.

- [ ] **Step 3: GameSaveData에 reputation 추가**

`lib/core/save.dart`를 수정한다.

(a) 생성자에 파라미터 추가(`tutorialSeen = true,` 다음, 59행 부근):

```dart
    this.reputation = defaultReputation,
```

(b) `fromJson`에 필드 추가(`tutorialSeen: ...` 다음, 78행 부근):

```dart
      // v6 이하 저장에는 reputation이 없다 → 기본값으로 마이그레이션.
      reputation: (json['reputation'] as num?)?.toDouble() ?? defaultReputation,
```

(c) 버전 주석·상수 갱신(86~87행):

```dart
  /// v5 → v6: tutorialSeen 추가 (없으면 true — 기존 유저는 생략).
  /// v6 → v7: reputation 추가 (없으면 defaultReputation).
  static const int currentVersion = 7;

  /// reputation 미보유 저장의 기본 평판.
  static const double defaultReputation = 70;
```

(d) 필드 선언 추가(`final bool tutorialSeen;` 다음, 104행 부근):

```dart
  /// 휴게소 평판(0~100).
  final double reputation;
```

(e) `toJson`에 추가(`'tutorialSeen': tutorialSeen,` 다음, 114행 부근):

```dart
        'reputation': reputation,
```

- [ ] **Step 4: 저장 테스트 통과 확인**

Run: `fvm flutter test test/save_test.dart`
Expected: PASS.

- [ ] **Step 5: 게임의 저장/복원 배선**

`lib/game/highway_tycoon_game.dart`:

(a) `_currentSaveData()`(428행 부근)의 `GameSaveData(...)` 인자에 `tutorialSeen: _tutorialSeen,` 다음 줄로 추가:

```dart
      reputation: _reputation,
```

(b) onLoad 복원부에서 `_questIndex = data.questIndex.clamp(...)`(336행 부근) **위**에 추가:

```dart
    _reputation = data.reputation;
    reputation.value = _reputation;
```

- [ ] **Step 6: 복원 테스트 추가**

`test/reputation_test.dart`의 `group('평판 시스템', () {` 안에 추가한다.

```dart
    test('저장된 평판이 재시작 시 복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final game = HighwayTycoonGame();
      await game.onLoad();
      game.debugReputation = 33;
      await game.saveNow();

      final reloaded = HighwayTycoonGame();
      await reloaded.onLoad();
      expect(reloaded.debugReputation, 33);
    });
```

Run: `fvm flutter test test/reputation_test.dart test/save_test.dart`
Expected: PASS.

- [ ] **Step 7: 커밋**

```bash
git add lib/core/save.dart lib/game/highway_tycoon_game.dart test/save_test.dart test/reputation_test.dart
git commit -m "feat(save): 평판 영속화 v6→v7 + 복원"
```

---

## Task 5: 이탈 차량 "놓침" 플로팅 시각화

**Files:**
- Modify: `lib/game/highway_tycoon_game.dart`
- Test: `test/reputation_test.dart`

- [ ] **Step 1: 실패하는 테스트 추가**

`test/reputation_test.dart`의 `group('평판 시스템', () {` 안에 추가한다.

```dart
    test('이탈 시 놓침 플로팅 텍스트가 추가된다', () async {
      final game = await createGame();
      final before = game.debugFloatingSaleTextCount;
      game.debugRegisterLostVehicle();
      expect(game.debugFloatingSaleTextCount, before + 1);
    });
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `fvm flutter test test/reputation_test.dart`
Expected: FAIL — `_registerLostVehicle`가 아직 플로팅을 추가하지 않음.

- [ ] **Step 3: FloatingSaleText에 색상 필드 추가**

`lib/game/highway_tycoon_game.dart`의 `class FloatingSaleText`(2454행 부근)를 아래로 교체한다.

```dart
class FloatingSaleText {
  FloatingSaleText({
    required this.position,
    required this.text,
    this.color = const Color(0xFFFFE082),
  });

  Offset position;
  final String text;
  final Color color;
  double age = 0;
}
```

- [ ] **Step 4: 렌더가 색상 필드를 쓰도록 수정**

`_drawFloatingSaleTexts`(491행 부근)에서 `color: const Color(0xFFFFE082).withValues(alpha: opacity),`(499행)를 아래로 교체한다.

```dart
            color: floating.color.withValues(alpha: opacity),
```

- [ ] **Step 5: `_registerLostVehicle`가 놓침 플로팅을 추가**

Task 2에서 만든 `_registerLostVehicle`의 본문 끝(`congestion.value = _lostToday;` 다음)에 추가한다.

```dart
    _floatingSaleTexts.add(
      FloatingSaleText(
        position: position - const Offset(0, 16),
        text: '놓침',
        color: const Color(0xFFE57373),
      ),
    );
```

- [ ] **Step 6: 테스트 통과 확인**

Run: `fvm flutter test test/reputation_test.dart`
Expected: PASS.

- [ ] **Step 7: 커밋**

```bash
git add lib/game/highway_tycoon_game.dart test/reputation_test.dart
git commit -m "feat(game): 이탈 차량 '놓침' 플로팅(빨강) 시각화"
```

---

## Task 6: HUD — 평판 배지 + 정체 경고

**Files:**
- Modify: `lib/app.dart`

이 Task는 UI라 유닛 테스트 대신 `analyze` + 시뮬레이터 스모크(Task 7)로 검증한다.

- [ ] **Step 1: 평판 배지 추가**

`lib/app.dart`의 좌상단 Column에서 퀘스트 배너 `ValueListenableBuilder<String?>`(402~430행) **다음**, `const SizedBox(height: 8),`를 하나 넣고 아래 위젯을 추가한다(quest 배너 블록 닫는 `),` 다음).

```dart
                      const SizedBox(height: 8),
                      ValueListenableBuilder<double>(
                        valueListenable: game.reputation,
                        builder: (context, value, _) {
                          final rep = value.round();
                          // 평판이 낮을수록 붉게, 높을수록 초록으로.
                          final color = Color.lerp(
                            const Color(0xFFE57373),
                            const Color(0xFF9CD98B),
                            (value / 100).clamp(0.0, 1.0),
                          )!;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC1E1A16),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color),
                            ),
                            child: Text(
                              '평판 $rep',
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          );
                        },
                      ),
```

- [ ] **Step 2: 정체 경고 배지 추가**

바로 위 평판 배지 다음에 추가한다.

```dart
                      ValueListenableBuilder<int>(
                        valueListenable: game.congestion,
                        builder: (context, value, _) {
                          if (value <= 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xCC4A2C2C),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0x66E57373)),
                              ),
                              child: Text(
                                '정체 · 오늘 놓친 손님 $value대',
                                style: const TextStyle(
                                  color: Color(0xFFFFCDD2),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
```

- [ ] **Step 3: 정적 분석 확인**

Run: `fvm flutter analyze`
Expected: `No issues found!` (경고 0).

- [ ] **Step 4: 커밋**

```bash
git add lib/app.dart
git commit -m "feat(ui): 평판 배지 + 정체 경고 HUD"
```

---

## Task 7: 전체 검증 (분석·테스트·시뮬레이터 스모크)

**Files:** 없음(검증 전용).

- [ ] **Step 1: 정적 분석**

Run: `fvm flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 전체 유닛 테스트**

Run: `fvm flutter test`
Expected: 모든 테스트 PASS.

- [ ] **Step 3: 시뮬레이터 스모크 검증** (메모리 지침: 시뮬레이터 직접 검증 필수)

`/run-reststop-tycoon` 스킬 절차로 앱을 빌드·실행하고 다음을 관찰한다:
1. HUD 좌상단에 **평판 배지**가 뜬다(시작 70, 노랑~초록 경계 색).
2. 매장을 여러 개 지어 유입을 늘리고 주차를 부족하게 두면, 대기열이 차고 **이탈 차량에 빨간 "놓침"** 플로팅이 뜬다.
3. **"정체 · 오늘 놓친 손님 N대"** 경고 배지가 나타나고 평판 배지 숫자·색이 하락한다.
4. `주차`를 확장해 수용을 늘리면 이탈이 줄고 평판이 서서히 회복된다.

Expected: 위 4단계가 관찰됨(스크린샷으로 기록).

- [ ] **Step 4: 최종 커밋(필요 시)**

검증 중 조정이 있었다면 커밋한다.

```bash
git add -A
git commit -m "test: 정체 완화 루프 Phase 1 시뮬레이터 검증"
```

---

## Self-Review 메모(작성자 확인 완료)

- **스펙 커버리지:** 평판(Task 2)·수요 피드백(Task 3)·가시화 HUD/플로팅(Task 5·6)·주차 완화 통합(기존 엔진, Task 7 검증)·밸런스 훅(Task 1)·저장 v7(Task 4) 모두 태스크로 매핑됨. 포장주차는 스코프에서 명시적으로 제외(Phase 2).
- **타입 일관성:** `reputation`(ValueNotifier<double>)·`congestion`(ValueNotifier<int>)·`_reputation`(double)·`_lostToday`(int)·`GameSaveData.reputation`(double)·`Balance.demandFactor(double)`·`_registerLostVehicle(Offset)`·`FloatingSaleText.color`(Color) — 태스크 전반에서 이름/시그니처 일치.
- **플레이스홀더 없음.**
