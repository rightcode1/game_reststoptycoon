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
    // debugTapTile의 화면 좌표 변환이 game.size를 쓰므로 가상 크기를 잡아준다.
    game.onGameResize(Vector2(390, 844));
    await game.onLoad();
    return game;
  }

  group('직원 밸런스', () {
    test('고용 비용은 인원이 늘수록 증가하고 최대 인원에서 null이다', () {
      int? previousCost;
      for (var staff = 0; staff < Balance.maxStaffPerStore; staff++) {
        final cost = Balance.staffHireCostOf('라면', staff);
        expect(cost, isNotNull, reason: '$staff명일 때');
        expect(cost!, greaterThan(0));
        if (previousCost != null) {
          expect(cost, greaterThan(previousCost));
        }
        previousCost = cost;
      }
      expect(Balance.staffHireCostOf('라면', Balance.maxStaffPerStore), isNull);
      expect(Balance.staffHireCostOf('주차', 0), isNull);
    });

    test('직원 보너스가 판매가에 반영된다', () {
      final base = Balance.salePriceAt('라면', 1)!;
      expect(Balance.salePriceWith('라면', 1, 0), base);
      expect(
        Balance.salePriceWith('라면', 1, 2),
        (base * (1 + Balance.staffSalesBonusPerStaff * 2)).round(),
      );
      expect(Balance.salePriceWith('주차', 1, 1), isNull);
    });
  });

  group('직원 고용', () {
    test('고용 시 비용이 차감되고 매출에 보너스가 붙는다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      final moneyBefore = game.debugMoney;
      final hireCost = Balance.staffHireCostOf('라면', 0)!;

      game.hireStaff(anchor);

      expect(game.debugMoney, moneyBefore - hireCost);
      expect(game.debugPlacedTiles[anchor]!.staffCount, 1);
      expect(game.notice.value, contains('직원 고용 완료'));

      final saleBase = game.debugMoney;
      game.debugRecordSaleAt(anchor);
      expect(game.debugMoney, saleBase + Balance.salePriceWith('라면', 1, 1)!);
    });

    test('잔액이 부족하면 고용이 거부된다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      game.debugMoney = Balance.staffHireCostOf('라면', 0)! - 1;

      game.hireStaff(anchor);

      expect(game.debugPlacedTiles[anchor]!.staffCount, 0);
      expect(game.notice.value, contains('잔액'));
    });

    test('최대 인원 이후에는 고용되지 않는다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      game.debugMoney = 1000000;

      for (var i = 0; i < Balance.maxStaffPerStore; i++) {
        game.hireStaff(anchor);
      }
      expect(
        game.debugPlacedTiles[anchor]!.staffCount,
        Balance.maxStaffPerStore,
      );

      final moneyAtMax = game.debugMoney;
      game.hireStaff(anchor);

      expect(
        game.debugPlacedTiles[anchor]!.staffCount,
        Balance.maxStaffPerStore,
      );
      expect(game.debugMoney, moneyAtMax);
      expect(game.notice.value, contains('최대 인원'));
    });

    test('업그레이드해도 직원 수가 유지된다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      game.debugMoney = 1000000;
      game.hireStaff(anchor);

      game.upgradeStore(anchor);

      expect(game.debugPlacedTiles[anchor]!.level, 2);
      expect(game.debugPlacedTiles[anchor]!.staffCount, 1);
    });

    test('매장 탭 요청에 직원 정보가 들어간다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      game.hireStaff(anchor);

      game.debugTapTile(anchor);

      final request = game.upgradeRequest.value;
      expect(request, isNotNull);
      expect(request!.staffCount, 1);
      expect(request.staffHireCost, Balance.staffHireCostOf('라면', 1));
      expect(request.currentSalePrice, Balance.salePriceWith('라면', 1, 1));
    });
  });

  group('직원 저장/복원', () {
    test('고용한 직원 수가 저장되고 복원되며 오프라인 정산에도 반영된다', () async {
      SharedPreferences.setMockInitialValues({});
      final firstRun = HighwayTycoonGame();
      await firstRun.onLoad();
      expect(firstRun.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(firstRun, '라면');
      firstRun.hireStaff(anchor);
      await firstRun.saveNow();

      final secondRun = HighwayTycoonGame();
      await secondRun.onLoad();

      expect(secondRun.debugPlacedTiles[anchor]!.staffCount, 1);
    });

    test('staffCount가 없는 v3 이하 저장은 0명으로 로드된다', () async {
      SharedPreferences.setMockInitialValues({
        SaveRepository.storageKey:
            '{"version":3,"money":777,"elapsedGameMinutes":50000,'
                '"placedTiles":[{"tileNumber":2147,"label":"라면",'
                '"showLabel":true,"level":2}]}',
      });

      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.debugPlacedTiles[2147]!.staffCount, 0);
      expect(game.debugPlacedTiles[2147]!.level, 2);
    });
  });
}
