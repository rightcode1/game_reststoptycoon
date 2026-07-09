import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/core/save.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

int storeAnchorOf(HighwayTycoonGame game, String name) {
  return game.debugPlacedTiles.entries
      .firstWhere((entry) => entry.value.showLabel && entry.value.label == name)
      .key;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HighwayTycoonGame> createGame() async {
    SharedPreferences.setMockInitialValues({});
    final game = HighwayTycoonGame();
    // 헤드리스 테스트에는 레이아웃이 없으므로 가상 화면 크기를 잡아준다.
    // (debugTapTile 등 화면 좌표 변환이 game.size를 사용)
    game.onGameResize(Vector2(390, 844));
    await game.onLoad();
    return game;
  }

  group('업그레이드 밸런스 곡선', () {
    test('업그레이드 비용은 레벨이 오를수록 증가하고 최대 레벨에서 null이다', () {
      int? previousCost;
      for (var level = 1; level < Balance.storeMaxLevel; level++) {
        final cost = Balance.upgradeCostOf('라면', level);
        expect(cost, isNotNull, reason: 'Lv.$level');
        expect(cost!, greaterThan(0));
        if (previousCost != null) {
          expect(cost, greaterThan(previousCost));
        }
        previousCost = cost;
      }
      expect(Balance.upgradeCostOf('라면', Balance.storeMaxLevel), isNull);
      expect(Balance.upgradeCostOf('주차', 1), isNull);
      expect(Balance.upgradeCostOf('없는 매장', 1), isNull);
    });

    test('판매가는 레벨이 오를수록 증가한다', () {
      int? previousPrice;
      for (var level = 1; level <= Balance.storeMaxLevel; level++) {
        final price = Balance.salePriceAt('라면', level);
        expect(price, isNotNull);
        if (previousPrice != null) {
          expect(price!, greaterThan(previousPrice));
        }
        previousPrice = price;
      }
      expect(Balance.salePriceAt('라면', 1), Balance.salePriceOf('라면'));
      expect(Balance.salePriceAt('주차', 1), isNull);
    });
  });

  group('매장 업그레이드', () {
    test('업그레이드 시 비용이 차감되고 레벨과 판매가가 오른다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      final moneyBefore = game.debugMoney;
      final upgradeCost = Balance.upgradeCostOf('라면', 1)!;

      game.upgradeStore(anchor);

      expect(game.debugMoney, moneyBefore - upgradeCost);
      expect(game.debugPlacedTiles[anchor]!.level, 2);
      expect(game.notice.value, contains('Lv.2'));

      // 업그레이드된 매장의 매출은 레벨 반영 판매가를 쓴다.
      final saleBase = game.debugMoney;
      game.debugRecordSaleAt(anchor);
      expect(game.debugMoney, saleBase + Balance.salePriceAt('라면', 2)!);
    });

    test('잔액이 부족하면 업그레이드가 거부된다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      game.debugMoney = Balance.upgradeCostOf('라면', 1)! - 1;

      game.upgradeStore(anchor);

      expect(game.debugPlacedTiles[anchor]!.level, 1);
      expect(game.notice.value, contains('잔액'));
    });

    test('최대 레벨에서는 더 이상 업그레이드되지 않는다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      game.debugMoney = 1000000;

      for (var i = 1; i < Balance.storeMaxLevel; i++) {
        game.upgradeStore(anchor);
      }
      expect(game.debugPlacedTiles[anchor]!.level, Balance.storeMaxLevel);

      final moneyAtMax = game.debugMoney;
      game.upgradeStore(anchor);

      expect(game.debugPlacedTiles[anchor]!.level, Balance.storeMaxLevel);
      expect(game.debugMoney, moneyAtMax);
      expect(game.notice.value, contains('최대 레벨'));
    });
  });

  group('매장 탭 → 업그레이드 요청', () {
    test('배치된 매장을 탭하면 업그레이드 요청이 발행된다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');

      game.debugTapTile(anchor);

      final request = game.upgradeRequest.value;
      expect(request, isNotNull);
      expect(request!.storeName, '라면');
      expect(request.level, 1);
      expect(request.anchorTileNumber, anchor);
      expect(request.upgradeCost, Balance.upgradeCostOf('라면', 1));
      expect(request.currentSalePrice, Balance.salePriceAt('라면', 1));
    });

    test('매장의 아래쪽 발자국 타일을 탭해도 같은 앵커로 연결된다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      final lowerTile = game.debugPlacedTiles.keys
          .firstWhere((tileNumber) => tileNumber != anchor);

      game.debugTapTile(lowerTile);

      expect(game.upgradeRequest.value?.anchorTileNumber, anchor);
    });

    test('주차 시설이나 빈 타일 탭은 요청을 만들지 않는다', () async {
      final game = await createGame();
      expect(game.debugBuild('주차'), isTrue);
      final parkingTile = game.debugPlacedTiles.keys.first;

      game.debugTapTile(parkingTile);
      game.debugTapTile(2147); // 빈 상업 타일

      expect(game.upgradeRequest.value, isNull);
    });
  });

  group('레벨 저장/복원', () {
    test('업그레이드한 레벨이 저장되고 새 게임 인스턴스에서 복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final firstRun = HighwayTycoonGame();
      await firstRun.onLoad();
      expect(firstRun.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(firstRun, '라면');
      firstRun.upgradeStore(anchor);
      await firstRun.saveNow();

      final secondRun = HighwayTycoonGame();
      await secondRun.onLoad();

      expect(secondRun.debugPlacedTiles[anchor]!.level, 2);
    });

    test('level 필드가 없는 v1 저장도 레벨 1로 로드된다', () async {
      SharedPreferences.setMockInitialValues({
        SaveRepository.storageKey:
            '{"version":1,"money":777,"elapsedGameMinutes":46000,'
                '"placedTiles":[{"tileNumber":2147,"label":"라면",'
                '"showLabel":true}]}',
      });

      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.debugMoney, 777);
      expect(game.debugPlacedTiles[2147]!.level, 1);
    });
  });
}
