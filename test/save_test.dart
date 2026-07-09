import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/core/save.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameSaveData 직렬화', () {
    test('toJson → fromJson 왕복이 값을 보존한다', () {
      const original = GameSaveData(
        money: 12345,
        elapsedGameMinutes: 98765.5,
        placedTiles: [
          PlacedTileSave(tileNumber: 2147, label: '라면', showLabel: true),
          PlacedTileSave(tileNumber: 2177, label: '라면', showLabel: false),
        ],
      );

      final restored = GameSaveData.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.version, GameSaveData.currentVersion);
      expect(restored.money, original.money);
      expect(restored.elapsedGameMinutes, original.elapsedGameMinutes);
      expect(restored.placedTiles.length, 2);
      expect(restored.placedTiles.first.tileNumber, 2147);
      expect(restored.placedTiles.first.label, '라면');
      expect(restored.placedTiles.first.showLabel, isTrue);
      expect(restored.placedTiles.last.showLabel, isFalse);
    });
  });

  group('SaveRepository', () {
    test('저장이 없으면 null을 반환한다', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await SaveRepository().load(), isNull);
    });

    test('save 후 load하면 같은 데이터가 돌아온다', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SaveRepository();
      const data = GameSaveData(
        money: 777,
        elapsedGameMinutes: 50000,
        placedTiles: [
          PlacedTileSave(tileNumber: 2147, label: '국밥', showLabel: true),
        ],
      );

      await repository.save(data);
      final loaded = await repository.load();

      expect(loaded, isNotNull);
      expect(loaded!.money, 777);
      expect(loaded.elapsedGameMinutes, 50000);
      expect(loaded.placedTiles.single.label, '국밥');
    });

    test('손상된 저장 데이터는 null(새 게임)로 처리한다', () async {
      SharedPreferences.setMockInitialValues({
        SaveRepository.storageKey: '이건 JSON이 아님 {{{',
      });

      expect(await SaveRepository().load(), isNull);
    });

    test('clear하면 저장이 사라진다', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SaveRepository();
      await repository.save(
        const GameSaveData(money: 1, elapsedGameMinutes: 2, placedTiles: []),
      );

      await repository.clear();

      expect(await repository.load(), isNull);
    });
  });

  group('게임 저장/복원 통합', () {
    test('건설 후 저장하면 새 게임 인스턴스에서 돈과 시설이 복원된다', () async {
      SharedPreferences.setMockInitialValues({});

      final firstRun = HighwayTycoonGame();
      await firstRun.onLoad();
      expect(firstRun.debugBuild('라면'), isTrue);
      await firstRun.saveNow();

      final secondRun = HighwayTycoonGame();
      await secondRun.onLoad();

      // 건설비 차감 + 첫 매장 퀘스트 보상(+400원)이 복원된다.
      expect(
        secondRun.debugMoney,
        Balance.startingMoney - Balance.buildCostOf('라면')! + 400,
      );
      expect(secondRun.moneyLabel.value, '자금 19,900원');
      // 배치 시설 복원: 라면 매장(세로 2타일)이 그대로 살아있다.
      final labels =
          secondRun.debugPlacedTiles.values.map((tile) => tile.label).toSet();
      expect(labels, {'라면'});
      expect(secondRun.debugPlacedTiles.length, 2);
      // 복원된 매장으로 방문 계획도 정상 동작한다.
      expect(secondRun.debugPlanStoreVisit(2092), isNotNull);
    });

    test('저장된 게임 시간이 HUD에 복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SaveRepository();
      // 50,000게임분 = 2월 5일 17시 20분
      await repository.save(
        const GameSaveData(
          money: 777,
          elapsedGameMinutes: 50000,
          placedTiles: [],
        ),
      );

      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.debugMoney, 777);
      expect(game.timeLabel.value, '2월 5일 17시 20분');
    });

    test('맵에 존재하지 않는 타일 번호가 저장돼 있어도 무시하고 로드된다', () async {
      SharedPreferences.setMockInitialValues({});
      await SaveRepository().save(
        const GameSaveData(
          money: 500,
          elapsedGameMinutes: 60000,
          placedTiles: [
            PlacedTileSave(tileNumber: 999999, label: '라면', showLabel: true),
          ],
        ),
      );

      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.debugMoney, 500);
      expect(game.debugPlacedTiles, isEmpty);
    });
  });
}
