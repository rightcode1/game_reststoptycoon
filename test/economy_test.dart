import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

/// 주차 슬롯 타일 번호(게임의 하드코딩 값과 동일).
const int parkingSpotTileNumber = 2092;

/// 배치된 매장의 앵커(showLabel) 타일 번호를 찾는다.
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
    await game.onLoad();
    return game;
  }

  group('건설 비용', () {
    test('식당 건설 시 건설비가 차감되고 HUD 라벨이 갱신된다', () async {
      final game = await createGame();
      final cost = Balance.buildCostOf('라면')!;

      expect(game.debugBuild('라면'), isTrue);

      // 첫 매장 건설 퀘스트 보상(+400원)이 함께 반영된다.
      expect(game.debugMoney, Balance.startingMoney - cost + 400);
      expect(game.moneyLabel.value, '자금 19,900원');
    });

    test('잔액이 부족하면 건설이 거부되고 돈이 줄지 않는다', () async {
      final game = await createGame();
      game.debugMoney = Balance.buildCostOf('라면')! - 1;

      expect(game.debugBuild('라면'), isFalse);

      expect(game.debugMoney, Balance.buildCostOf('라면')! - 1);
    });

    test('잔액 부족 시 안내 메시지가 발행된다', () async {
      final game = await createGame();
      game.debugMoney = 0;
      expect(game.notice.value, isNull);

      expect(game.debugBuild('라면'), isFalse);

      expect(game.notice.value, isNotNull);
      expect(game.notice.value, contains('잔액'));
      expect(game.notice.value, contains('500'));
    });

    test('카페/디저트 매장도 건설비가 차감된다', () async {
      final game = await createGame();
      final cost = Balance.buildCostOf('핫도그')!;

      expect(game.debugBuild('핫도그'), isTrue);

      // 첫 매장 건설 퀘스트 보상(+400원)이 함께 반영된다.
      expect(game.debugMoney, Balance.startingMoney - cost + 400);
      // 세로 2타일 매장으로 배치된다.
      expect(game.debugPlacedTiles.length, 2);
    });
  });

  group('배치 모드', () {
    test('배치 시작·취소가 pendingPlacementLabel에 반영된다', () async {
      final game = await createGame();
      expect(game.pendingPlacementLabel.value, isNull);

      game.startPlacement('라면');
      expect(game.pendingPlacementLabel.value, '라면');

      game.cancelPlacement();
      expect(game.pendingPlacementLabel.value, isNull);
      expect(game.debugMoney, Balance.startingMoney);
    });
  });

  group('매출 발생', () {
    test('방문객이 매장에 도착하면 판매가만큼 돈이 늘어난다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      final before = game.debugMoney;

      game.debugRecordSaleAt(anchor);

      expect(game.debugMoney, before + Balance.storeSpecs['라면']!.salePrice);
      expect(game.moneyLabel.value, contains('원'));
    });

    test('매장이 아닌 타일은 매출을 만들지 않는다', () async {
      final game = await createGame();
      expect(game.debugBuild('주차'), isTrue);
      final parkingTile = game.debugPlacedTiles.keys.first;
      final before = game.debugMoney;

      game.debugRecordSaleAt(parkingTile); // 주차 시설
      game.debugRecordSaleAt(999999); // 존재하지 않는 타일

      expect(game.debugMoney, before);
    });

    test('판매 시 +금액 플로팅 텍스트가 생기고 수명이 다하면 사라진다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      expect(game.debugFloatingSaleTextCount, 0);

      game.debugRecordSaleAt(anchor);
      expect(game.debugFloatingSaleTextCount, 1);

      game.update(0.7); // 수명(1.4초)의 절반 → 아직 표시 중
      expect(game.debugFloatingSaleTextCount, 1);

      game.update(1.0); // 수명 초과 → 제거
      expect(game.debugFloatingSaleTextCount, 0);
    });

    test('매출이 누적된다', () async {
      final game = await createGame();
      expect(game.debugBuild('국밥'), isTrue);
      final anchor = storeAnchorOf(game, '국밥');
      final before = game.debugMoney;
      final salePrice = Balance.storeSpecs['국밥']!.salePrice;

      game.debugRecordSaleAt(anchor);
      game.debugRecordSaleAt(anchor);
      game.debugRecordSaleAt(anchor);

      expect(game.debugMoney, before + salePrice * 3);
    });
  });

  group('매장 방문 계획', () {
    test('배치된 매장이 없으면 방문 계획이 없다', () async {
      final game = await createGame();

      expect(game.debugPlanStoreVisit(parkingSpotTileNumber), isNull);
    });

    test('매장을 지으면 주차 슬롯에서 매장 앞까지 경로가 잡힌다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);

      final plan = game.debugPlanStoreVisit(parkingSpotTileNumber);

      expect(plan, isNotNull);
      expect(plan!.storeName, '라면');
      expect(plan.path.first, parkingSpotTileNumber);
      expect(plan.path.length, greaterThanOrEqualTo(2));
      // 경로에 중복 타일이 없어야 한다(BFS 최단 경로).
      expect(plan.path.toSet().length, plan.path.length);
    });

    test('여러 매장이 있으면 그중 하나가 방문 대상으로 선택된다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      expect(game.debugBuild('국밥'), isTrue);

      final plan = game.debugPlanStoreVisit(parkingSpotTileNumber);

      expect(plan, isNotNull);
      expect(['라면', '국밥'], contains(plan!.storeName));
    });

    test('카페/디저트 매장도 방문·구매 대상이 된다', () async {
      final game = await createGame();
      expect(game.debugBuild('핫도그'), isTrue);

      final plan = game.debugPlanStoreVisit(parkingSpotTileNumber);
      expect(plan, isNotNull);
      expect(plan!.storeName, '핫도그');
      expect(plan.anchorTileNumber, storeAnchorOf(game, '핫도그'));

      final before = game.debugMoney;
      game.debugRecordSaleAt(plan.anchorTileNumber);
      expect(
        game.debugMoney,
        before + Balance.storeSpecs['핫도그']!.salePrice,
      );
    });
  });
}
