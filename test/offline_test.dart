import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/core/save.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 7, 9, 12);

  Future<HighwayTycoonGame> loadGameWith(
    GameSaveData save, {
    DateTime? now,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await SaveRepository().save(save);
    final game = HighwayTycoonGame(clock: () => now ?? fixedNow);
    await game.onLoad();
    return game;
  }

  group('오프라인 수익 정산', () {
    test('부재 1시간(=10게임일)만큼 시계가 전진하고 매장 수익이 정산된다', () async {
      final game = await loadGameWith(
        GameSaveData(
          money: 1000,
          elapsedGameMinutes: 50000,
          placedTiles: const [
            PlacedTileSave(
              tileNumber: 2147,
              label: '라면',
              showLabel: true,
              level: 2,
            ),
          ],
          savedAtEpochMs: fixedNow
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ),
      );

      // 1시간 현실 = 3,600초 × 4게임분 = 14,400게임분 = 10게임일
      expect(game.debugElapsedGameMinutes, 50000 + 14400);

      final expectedAmount =
          (Balance.salePriceAt('라면', 2)! * Balance.offlineSalesPerStorePerDay * 10)
              .round();
      expect(game.debugMoney, 1000 + expectedAmount);
      expect(game.offlineEarnings.value, isNotNull);
      expect(game.offlineEarnings.value!.amount, expectedAmount);
      expect(game.offlineEarnings.value!.offlineGameDays, closeTo(10, 0.001));
    });

    test('부재 시간은 최대 8시간까지만 인정된다', () async {
      final game = await loadGameWith(
        GameSaveData(
          money: 0,
          elapsedGameMinutes: 50000,
          placedTiles: const [
            PlacedTileSave(tileNumber: 2147, label: '라면', showLabel: true),
          ],
          savedAtEpochMs: fixedNow
              .subtract(const Duration(hours: 100))
              .millisecondsSinceEpoch,
        ),
      );

      // 8시간 = 28,800초 × 4게임분 = 115,200게임분 = 80게임일
      expect(game.debugElapsedGameMinutes, 50000 + 115200);
      final expectedAmount =
          (Balance.salePriceAt('라면', 1)! * Balance.offlineSalesPerStorePerDay * 80)
              .round();
      expect(game.debugMoney, expectedAmount);
    });

    test('매장이 없으면 시계만 전진하고 수익 다이얼로그는 없다', () async {
      final game = await loadGameWith(
        GameSaveData(
          money: 500,
          elapsedGameMinutes: 50000,
          placedTiles: const [],
          savedAtEpochMs: fixedNow
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ),
      );

      expect(game.debugElapsedGameMinutes, 50000 + 14400);
      expect(game.debugMoney, 500);
      expect(game.offlineEarnings.value, isNull);
    });

    test('저장 시각이 없는 v2 이하 저장은 정산을 건너뛴다', () async {
      final game = await loadGameWith(
        const GameSaveData(
          money: 500,
          elapsedGameMinutes: 50000,
          placedTiles: [
            PlacedTileSave(tileNumber: 2147, label: '라면', showLabel: true),
          ],
        ),
      );

      expect(game.debugElapsedGameMinutes, 50000);
      expect(game.debugMoney, 500);
      expect(game.offlineEarnings.value, isNull);
    });

    test('저장 시각이 미래(기기 시계 변경)면 무시한다', () async {
      final game = await loadGameWith(
        GameSaveData(
          money: 500,
          elapsedGameMinutes: 50000,
          placedTiles: const [
            PlacedTileSave(tileNumber: 2147, label: '라면', showLabel: true),
          ],
          savedAtEpochMs:
              fixedNow.add(const Duration(hours: 1)).millisecondsSinceEpoch,
        ),
      );

      expect(game.debugElapsedGameMinutes, 50000);
      expect(game.debugMoney, 500);
      expect(game.offlineEarnings.value, isNull);
    });

    test('저장 시 savedAtEpochMs가 기록된다', () async {
      SharedPreferences.setMockInitialValues({});
      final game = HighwayTycoonGame(clock: () => fixedNow);
      await game.onLoad();

      await game.saveNow();

      final loaded = await SaveRepository().load();
      expect(loaded!.savedAtEpochMs, fixedNow.millisecondsSinceEpoch);
    });
  });
}
