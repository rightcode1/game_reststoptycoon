# 부지 해금 확장 Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 초기엔 시작 부지만 열고, 잠긴 구역을 인접부터 점증 비용으로 해금하는 부지 확장 성장축을 추가한다.

**Architecture:** 50×50을 `landPlotSize`(=10) 격자 25플롯으로 나누고 `_unlockedPlots` 집합으로 관리. 잠금은 **건설(`_placementFootprintFor`)만 게이트**하고 경로/기본 슬롯엔 무관. 잠긴 타일 탭 → 인접 시 해금 다이얼로그. 렌더는 잠긴 타일을 딤 처리. 하드코딩 타일 번호는 안 건드린다.

**Tech Stack:** Flutter + Flame(수동 Canvas). 상태 `HighwayTycoonGame`, UI는 `ValueNotifier`. 저장 shared_preferences.

**참고 스펙:** [2026-07-09-land-unlock-expansion-phase2-design.md](../specs/2026-07-09-land-unlock-expansion-phase2-design.md)

---

## 파일 구조

- `lib/core/balance.dart` — `landPlotSize`, `landUnlockBaseCost`, `landUnlockCost(n)`.
- `lib/game/highway_tycoon_game.dart` — 플롯 헬퍼, `_unlockedPlots`, 시작셋, 배치 게이트, 탭-해금, `unlockPlot`, `landUnlockRequest` notifier, 렌더 딤, 디버그 시드.
- `lib/core/save.dart` — `unlockedPlots` v7→v8.
- `lib/app.dart` — 해금 다이얼로그 + dispose.
- `test/balance_test.dart` · `test/land_test.dart`(신규) · `test/save_test.dart`.

---

## Task 1: 플롯·해금 밸런스 상수

**Files:** Modify `lib/core/balance.dart`; Test `test/balance_test.dart`

- [ ] **Step 1: 실패 테스트 추가** — `test/balance_test.dart`의 마지막 그룹 닫힘 `});` 앞에:

```dart
    test('부지 해금 밸런스 수치가 유효하다', () {
      // 플롯 크기가 맵을 정확히 나눠야 격자가 어긋나지 않는다.
      expect(50 % Balance.landPlotSize, 0);
      expect(Balance.landUnlockBaseCost, greaterThan(0));
      // 점증: 해금할수록 비싸진다.
      expect(Balance.landUnlockCost(1), greaterThan(Balance.landUnlockCost(0)));
      expect(Balance.landUnlockCost(0), Balance.landUnlockBaseCost);
    });
```

- [ ] **Step 2: 실패 확인** — Run `fvm flutter test test/balance_test.dart` → FAIL(미정의).

- [ ] **Step 3: 구현** — `abstract final class Balance` 안(예: `gridlockGiveUpMinutes` 아래)에:

```dart
  /// 부지 플롯 한 변의 타일 수. 맵(50)을 정확히 나눠야 한다.
  static const int landPlotSize = 10;

  /// 첫 부지 해금 비용(점증 기준).
  static const int landUnlockBaseCost = 2000;

  /// n번째(시작분 제외) 부지 해금 비용. 점증.
  static int landUnlockCost(int unlockedBeyondStart) =>
      landUnlockBaseCost * (unlockedBeyondStart + 1);
```

- [ ] **Step 4: 통과 확인** — Run `fvm flutter test test/balance_test.dart` → PASS.

- [ ] **Step 5: 커밋**

```bash
git add lib/core/balance.dart test/balance_test.dart
git commit -m "feat(balance): 부지 플롯 크기·해금 점증 비용 상수"
```

---

## Task 2: 플롯 모델 + 시작셋 + 배치 게이트

**Files:** Modify `lib/game/highway_tycoon_game.dart`; Test `test/land_test.dart`(신규)

- [ ] **Step 1: 실패 테스트 작성** — `test/land_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HighwayTycoonGame> newGame() async {
    SharedPreferences.setMockInitialValues({});
    final game = HighwayTycoonGame();
    await game.onLoad();
    return game;
  }

  group('부지 해금', () {
    test('새 게임은 시작 플롯만 열려 있다(전체 25 미만)', () async {
      final game = await newGame();
      expect(game.debugUnlockedPlotCount, greaterThan(0));
      expect(game.debugUnlockedPlotCount, lessThan(25));
    });

    test('시작 부지 안에서는 첫 매장·첫 주차를 지을 수 있다', () async {
      final game = await newGame();
      game.debugMoney = 100000;
      expect(game.debugBuild('라면'), isTrue);
      expect(game.debugBuild('주차'), isTrue);
    });
  });
}
```

- [ ] **Step 2: 실패 확인** — Run `fvm flutter test test/land_test.dart` → FAIL(`debugUnlockedPlotCount` 미정의).

- [ ] **Step 3: 플롯 헬퍼·상태 추가** — 필드 선언부(`_reputation` 근처)에:

```dart
  final Set<int> _unlockedPlots = <int>{};
```

플롯 헬퍼(예: `_isPlotUnlocked`류가 쓰일 근처, `_placementFootprintFor` 위)에:

```dart
  static const int _plotsPerRow = mapColumns ~/ Balance.landPlotSize;

  int _plotKeyForTile(MapTile tile) =>
      ((tile.logicalX - 1) ~/ Balance.landPlotSize) * _plotsPerRow +
      ((tile.logicalY - 1) ~/ Balance.landPlotSize);

  int? _plotKeyForTileNumber(int tileNumber) {
    final tile = _tileByNumber[tileNumber];
    return tile == null ? null : _plotKeyForTile(tile);
  }

  bool _isPlotUnlocked(MapTile tile) =>
      _unlockedPlots.contains(_plotKeyForTile(tile));

  /// 기능적 시작 영역(초기 상업 2147 + 기본 주차 2092·2121)을 덮는 플롯.
  Set<int> _startingUnlockedPlots() {
    final keys = <int>{};
    for (final tileNumber in const [2147, 2092, 2121]) {
      final key = _plotKeyForTileNumber(tileNumber);
      if (key != null) keys.add(key);
    }
    return keys;
  }
```

- [ ] **Step 4: 시작셋 초기화** — `onLoad`에서 타일이 만들어진 뒤(월드/타일 초기화 직후, 저장 로드 전) 시작셋을 넣는다. `_syncDynamicParkingSlots()` 호출 근처보다 **앞**, 타일 빌드 직후에:

```dart
    _unlockedPlots
      ..clear()
      ..addAll(_startingUnlockedPlots());
```

그리고 `resetProgress`(데이터 초기화, `_reputation = Balance.reputationStart;` 근처)에도 동일하게:

```dart
    _unlockedPlots
      ..clear()
      ..addAll(_startingUnlockedPlots());
```

- [ ] **Step 5: 배치 게이트** — `_placementFootprintFor`에서 앵커/발자국 타일이 잠긴 플롯이면 거부. 시설(주차) 분기의 `return [anchorTile.tileNumber];` 앞과, 매장 분기의 footprint 루프 안에 잠금 검사를 넣는다. 함수 맨 앞(특수/기점유 검사 다음)에 앵커 검사 추가:

```dart
    if (!_isPlotUnlocked(anchorTile)) {
      return null;
    }
```

매장 발자국 루프의 조건에 잠금도 포함:

```dart
      if (tile == null ||
          tile.zone != TileZone.commercial ||
          !_isPlotUnlocked(tile) ||
          _specialLabelFor(tile) != null ||
          _placedTiles.containsKey(tile.tileNumber)) {
        return null;
      }
```

- [ ] **Step 6: 디버그 시드 추가** — 디버그 접근자 블록에:

```dart
  @visibleForTesting
  int get debugUnlockedPlotCount => _unlockedPlots.length;

  @visibleForTesting
  void debugUnlockAllPlots() {
    for (var i = 0; i < _plotsPerRow * (mapRows ~/ Balance.landPlotSize); i++) {
      _unlockedPlots.add(i);
    }
  }
```

- [ ] **Step 7: 통과 확인** — Run `fvm flutter test test/land_test.dart` → PASS. (시작 부지가 첫 매장/주차를 못 담으면 `_startingUnlockedPlots`에 인접 플롯을 더한다.)

- [ ] **Step 8: 회귀 확인 + 필요 시 개방 시드** — Run `fvm flutter test`. 카메라 근처만 짓는 기존 테스트는 시작 부지 안이라 통과해야 한다. 만약 특정 타일(먼 곳)을 `debugBuildAt`로 짓는 테스트가 잠금으로 실패하면, 그 테스트 setup에 `game.debugUnlockAllPlots();`를 추가한다(개별 최소 수정). `reputation_health_test`가 5매장+4주차로 시작 부지를 벗어나 실패하면 그 테스트 setup에도 `debugUnlockAllPlots()` 추가.

- [ ] **Step 9: 커밋**

```bash
git add lib/game/highway_tycoon_game.dart test/land_test.dart test/*.dart
git commit -m "feat(game): 부지 플롯 모델 + 시작셋 + 배치 잠금 게이트"
```

---

## Task 3: 탭-해금 상호작용

**Files:** Modify `lib/game/highway_tycoon_game.dart`; Test `test/land_test.dart`

- [ ] **Step 1: 실패 테스트 추가** — `group('부지 해금', ...)` 안에:

```dart
    test('인접 잠긴 플롯을 해금하면 비용이 차감되고 열린다', () async {
      final game = await newGame();
      game.debugMoney = 1000000;
      final target = game.debugFirstAdjacentLockedPlot();
      expect(target, isNotNull);
      final before = game.debugUnlockedPlotCount;
      final money = game.debugMoney;
      expect(game.unlockPlot(target!), isTrue);
      expect(game.debugUnlockedPlotCount, before + 1);
      expect(game.debugMoney, lessThan(money));
    });

    test('두 번째 해금은 첫 번째보다 비싸다(점증)', () async {
      final game = await newGame();
      game.debugMoney = 1000000;
      final first = game.debugFirstAdjacentLockedPlot()!;
      final m0 = game.debugMoney;
      game.unlockPlot(first);
      final cost1 = m0 - game.debugMoney;
      final second = game.debugFirstAdjacentLockedPlot()!;
      final m1 = game.debugMoney;
      game.unlockPlot(second);
      final cost2 = m1 - game.debugMoney;
      expect(cost2, greaterThan(cost1));
    });

    test('비인접·잔액부족 해금은 거부된다', () async {
      final game = await newGame();
      game.debugMoney = 0;
      final target = game.debugFirstAdjacentLockedPlot()!;
      expect(game.unlockPlot(target), isFalse); // 잔액 부족
    });
```

- [ ] **Step 2: 실패 확인** — Run `fvm flutter test test/land_test.dart` → FAIL(미정의).

- [ ] **Step 3: LandUnlockRequest 클래스 + notifier** — 파일 하단 데이터 클래스 근처에:

```dart
class LandUnlockRequest {
  const LandUnlockRequest({required this.plotKey, required this.cost});
  final int plotKey;
  final int cost;
}
```

notifier 선언부(`congestion` 근처)에:

```dart
  /// 잠긴 부지 탭 → UI 해금 다이얼로그 요청(플롯키·비용). 없으면 null.
  final ValueNotifier<LandUnlockRequest?> landUnlockRequest =
      ValueNotifier<LandUnlockRequest?>(null);
```

- [ ] **Step 4: 인접 판정·비용·해금 메서드** — 플롯 헬퍼 근처에:

```dart
  bool _isPlotAdjacentToUnlocked(int plotKey) {
    final px = plotKey ~/ _plotsPerRow;
    final py = plotKey % _plotsPerRow;
    const deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    for (final d in deltas) {
      final nx = px + d.$1;
      final ny = py + d.$2;
      final rows = mapRows ~/ Balance.landPlotSize;
      if (nx < 0 || nx >= _plotsPerRow || ny < 0 || ny >= rows) continue;
      if (_unlockedPlots.contains(nx * _plotsPerRow + ny)) return true;
    }
    return false;
  }

  int _currentLandUnlockCost() =>
      Balance.landUnlockCost(_unlockedPlots.length - _startingUnlockedPlots().length);

  /// 플롯을 해금한다. 인접·잔액 조건을 만족하면 true.
  bool unlockPlot(int plotKey) {
    if (_unlockedPlots.contains(plotKey) ||
        !_isPlotAdjacentToUnlocked(plotKey)) {
      return false;
    }
    final cost = _currentLandUnlockCost();
    if (_money < cost) {
      notice.value = '잔액이 부족합니다 — 부지 해금에 ${_formatNumber(cost)}원 필요';
      _playSound(GameSound.error);
      return false;
    }
    _money -= cost;
    moneyLabel.value = _formatMoney(_money);
    _unlockedPlots.add(plotKey);
    notice.value = '부지를 해금했습니다 (-${_formatNumber(cost)}원)';
    _playSound(GameSound.build);
    unawaited(saveNow());
    return true;
  }
```

- [ ] **Step 5: 탭 라우팅** — `_handleStoreTap` 시작부(placed 루프 앞)에 잠금 검사:

```dart
    final worldPoint = _screenToWorld(screenPoint, _zoom);
    for (final tile in _tiles) {
      if (!tile.path.contains(worldPoint)) continue;
      if (!_isPlotUnlocked(tile) && tile.logicalY < entryRoadStartY) {
        final key = _plotKeyForTile(tile);
        if (_isPlotAdjacentToUnlocked(key)) {
          landUnlockRequest.value =
              LandUnlockRequest(plotKey: key, cost: _currentLandUnlockCost());
        } else {
          notice.value = '인접한 구역만 해금할 수 있습니다';
        }
        return;
      }
      break;
    }
```

(기존 `final worldPoint = _screenToWorld(...)` 줄이 아래에 이미 있으면 중복 선언 제거 — worldPoint를 한 번만 선언하도록 병합.)

- [ ] **Step 6: 디버그 시드** — 디버그 블록에:

```dart
  @visibleForTesting
  int? debugFirstAdjacentLockedPlot() {
    final rows = mapRows ~/ Balance.landPlotSize;
    for (var key = 0; key < _plotsPerRow * rows; key++) {
      if (!_unlockedPlots.contains(key) && _isPlotAdjacentToUnlocked(key)) {
        return key;
      }
    }
    return null;
  }
```

- [ ] **Step 7: 통과 확인** — Run `fvm flutter test test/land_test.dart` → PASS.

- [ ] **Step 8: 커밋**

```bash
git add lib/game/highway_tycoon_game.dart test/land_test.dart
git commit -m "feat(game): 잠긴 부지 탭→인접 해금(unlockPlot·landUnlockRequest)"
```

---

## Task 4: 저장 v7 → v8 (해금 플롯 영속·마이그레이션)

**Files:** Modify `lib/core/save.dart`, `lib/game/highway_tycoon_game.dart`; Test `test/save_test.dart`, `test/land_test.dart`

- [ ] **Step 1: 실패 테스트 추가** — `test/save_test.dart` 직렬화 그룹에:

```dart
    test('unlockedPlots 왕복이 값을 보존한다', () {
      const original = GameSaveData(
        money: 1, elapsedGameMinutes: 0, placedTiles: [],
        unlockedPlots: [3, 7, 11],
      );
      final restored = GameSaveData.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.unlockedPlots, [3, 7, 11]);
    });

    test('unlockedPlots 없는 v7 저장은 null로 읽힌다(게임이 전체 개방 처리)', () {
      final restored = GameSaveData.fromJson({
        'version': 7, 'money': 1, 'elapsedGameMinutes': 0.0,
        'placedTiles': <dynamic>[],
      });
      expect(restored.unlockedPlots, isNull);
    });
```

- [ ] **Step 2: 실패 확인** — Run `fvm flutter test test/save_test.dart` → FAIL(미정의).

- [ ] **Step 3: GameSaveData 확장** — `lib/core/save.dart`:

생성자에 `this.unlockedPlots,`(nullable, 기본 없음) 추가(`reputation` 다음).
fromJson에:

```dart
      // v7 이하 저장에는 없다 → null(게임이 전체 개방으로 마이그레이션).
      unlockedPlots: (json['unlockedPlots'] as List<dynamic>?)
          ?.map((e) => e as int)
          .toList(),
```

버전/필드/`toJson`:

```dart
  /// v6 → v7: reputation 추가.
  /// v7 → v8: unlockedPlots 추가 (없으면 게임이 전체 개방으로 마이그레이션).
  static const int currentVersion = 8;
```
```dart
  /// 해금된 부지 플롯키 목록. null이면 구버전(전체 개방).
  final List<int>? unlockedPlots;
```
`toJson`에 `if (unlockedPlots != null) 'unlockedPlots': unlockedPlots,`.

- [ ] **Step 4: 저장 테스트 통과** — Run `fvm flutter test test/save_test.dart` → PASS.

- [ ] **Step 5: 게임 저장/복원 배선** — `_currentSaveData()`에 `unlockedPlots: _unlockedPlots.toList(),` 추가. `onLoad`의 저장 복원부(placedTiles 복원 뒤, `_syncDynamicParkingSlots` 근처)에서 저장이 있을 때:

```dart
    if (data.unlockedPlots != null) {
      _unlockedPlots
        ..clear()
        ..addAll(data.unlockedPlots!);
    } else {
      // v7 이하(기존 유저): 전체 개방으로 마이그레이션.
      debugUnlockAllPlots();
    }
```

(주의: 저장이 없는 완전 새 게임은 Task 2 Step 4의 시작셋 초기화가 유지되어야 하므로, 이 블록은 **저장이 존재해 복원하는 경로에서만** 실행되게 배치한다.)

- [ ] **Step 6: 복원 테스트 추가** — `test/land_test.dart`에:

```dart
    test('해금 상태가 저장·복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final game = HighwayTycoonGame();
      await game.onLoad();
      game.debugMoney = 1000000;
      final target = game.debugFirstAdjacentLockedPlot()!;
      game.unlockPlot(target);
      final count = game.debugUnlockedPlotCount;
      await game.saveNow();

      final reloaded = HighwayTycoonGame();
      await reloaded.onLoad();
      expect(reloaded.debugUnlockedPlotCount, count);
    });
```

Run `fvm flutter test test/land_test.dart test/save_test.dart` → PASS.

- [ ] **Step 7: 커밋**

```bash
git add lib/core/save.dart lib/game/highway_tycoon_game.dart test/save_test.dart test/land_test.dart
git commit -m "feat(save): 부지 해금 영속 v7→v8 + 구버전 전체개방 마이그레이션"
```

---

## Task 5: 잠긴 부지 렌더 딤

**Files:** Modify `lib/game/highway_tycoon_game.dart`

UI 렌더라 analyze + 스모크로 검증(유닛 테스트 없음).

- [ ] **Step 1: 잠긴 타일 어둡게** — 타일 렌더 루프에서 `canvas.drawPath(tile.path, borderPaint);`(타일 채색+테두리 직후, placementFootprint 강조 앞) 다음에:

```dart
      if (tile.logicalY < entryRoadStartY && !_isPlotUnlocked(tile)) {
        canvas.drawPath(
          tile.path,
          Paint()..color = const Color(0x99000000),
        );
      }
```

- [ ] **Step 2: 분석 확인** — Run `fvm flutter analyze` → `No issues found!`

- [ ] **Step 3: 커밋**

```bash
git add lib/game/highway_tycoon_game.dart
git commit -m "feat(render): 잠긴 부지 타일 딤 처리"
```

---

## Task 6: 해금 다이얼로그 (app.dart)

**Files:** Modify `lib/app.dart`

- [ ] **Step 1: 리스너 등록/해제 + notifier dispose** — `initState`에 `_game.landUnlockRequest.addListener(_onLandUnlockRequest);`(upgradeRequest 리스너 옆). `dispose`에 `_game.landUnlockRequest.removeListener(_onLandUnlockRequest);`와 `_game.landUnlockRequest.dispose();` 추가.

- [ ] **Step 2: 핸들러 추가** — `_onUpgradeRequest` 근처에:

```dart
  void _onLandUnlockRequest() {
    final request = _game.landUnlockRequest.value;
    if (request == null) return;
    _game.landUnlockRequest.value = null;
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2A2218),
        title: const Text('부지 해금',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text('이 부지를 ${request.cost}원에 해금할까요?',
            style: const TextStyle(
                color: Color(0xFFE7D7B7), fontWeight: FontWeight.w600)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              _game.unlockPlot(request.plotKey);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('해금'),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: 분석 확인** — Run `fvm flutter analyze` → `No issues found!`

- [ ] **Step 4: 커밋**

```bash
git add lib/app.dart
git commit -m "feat(ui): 부지 해금 확인 다이얼로그"
```

---

## Task 7: 전체 검증

**Files:** 없음.

- [ ] **Step 1: 분석** — Run `fvm flutter analyze` → `No issues found!`
- [ ] **Step 2: 전체 유닛** — Run `fvm flutter test` → 전부 PASS.
- [ ] **Step 3: 시뮬레이터 스모크**(메모리 지침 필수) — `/run-reststop-tycoon`로:
  1. 새 게임 시작 시 **잠긴 땅이 어둡게** 보이고 시작 부지만 밝다.
  2. 시작 부지 안에서 첫 매장·첫 주차가 지어진다.
  3. 잠긴(인접) 구역 탭 → **해금 다이얼로그** → 해금 후 그 땅이 밝아지고 건설 가능.
  4. 비인접 잠긴 구역 탭 → "인접한 구역만..." 안내.
  스크린샷 기록.
- [ ] **Step 4: 최종 커밋(필요 시)**

---

## Self-Review 메모(작성자 확인)

- **스펙 커버리지:** 플롯 모델·게이트(T2)·해금 상호작용/점증(T3)·비용(T1)·렌더 딤(T5)·다이얼로그(T6)·저장 v8/마이그레이션(T4)·검증(T7) 매핑됨.
- **타입 일관성:** `_unlockedPlots`(Set<int>)·`plotKey`(int)·`_plotsPerRow`(int)·`unlockPlot(int)→bool`·`LandUnlockRequest{plotKey,cost}`·`landUnlockRequest`(ValueNotifier<LandUnlockRequest?>)·`GameSaveData.unlockedPlots`(List<int>?)·`Balance.landUnlockCost(int)→int` 일치.
- **회귀 리스크:** 배치 잠금이 기존 테스트를 깰 수 있음 → T2 Step 8에서 전체 스위트 돌려 `debugUnlockAllPlots()`로 최소 대응.
