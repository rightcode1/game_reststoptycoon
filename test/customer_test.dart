import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

const int parkingSpotTileNumber = 2092;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HighwayTycoonGame> createGame() async {
    SharedPreferences.setMockInitialValues({});
    final game = HighwayTycoonGame();
    await game.onLoad();
    return game;
  }

  group('개인별 매장 선택', () {
    test('도달 가능한 매장 목록에 배치된 매장이 전부 들어간다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      expect(game.debugBuild('국밥'), isTrue);

      final plans = game.debugReachableStorePlans(parkingSpotTileNumber);

      expect(plans.length, 2);
      expect(
        plans.map((plan) => plan.storeName).toSet(),
        {'라면', '국밥'},
      );
      for (final plan in plans) {
        expect(plan.path.first, parkingSpotTileNumber);
        expect(plan.path.length, greaterThanOrEqualTo(2));
      }
    });

    test('매장이 없으면 도달 가능 목록이 비어 있다', () async {
      final game = await createGame();

      expect(game.debugReachableStorePlans(parkingSpotTileNumber), isEmpty);
    });

    test('선호 가중치는 차량 유형별 수요 범위 중간값이다', () async {
      final game = await createGame();

      // 백반 트럭 수요 (2.0~4.0) → 3.0, 라면 트럭 수요 (0.4~1.0) → 0.7
      expect(game.debugStoreWeightFor('백반', VehicleType.truck), 3.0);
      expect(game.debugStoreWeightFor('라면', VehicleType.truck),
          closeTo(0.7, 0.0001));
      // 수요가 거의 없어도 최소 가중치는 보장된다.
      expect(
        game.debugStoreWeightFor('김치찌개', VehicleType.bus),
        greaterThanOrEqualTo(Balance.minStoreAffinity),
      );
      // 매장이 아니면 0.
      expect(game.debugStoreWeightFor('주차', VehicleType.sedan), 0);
    });

    test('트럭 승객은 수요 가중치가 높은 매장을 더 자주 고른다', () async {
      final game = await createGame();
      expect(game.debugBuild('백반'), isTrue); // 트럭 가중치 3.0
      expect(game.debugBuild('라면'), isTrue); // 트럭 가중치 0.7
      final plans = game.debugReachableStorePlans(parkingSpotTileNumber);
      expect(plans.length, 2);

      var baekbanCount = 0;
      const draws = 600;
      for (var i = 0; i < draws; i++) {
        final picked = game.debugPickWeightedStorePlan(
          plans,
          VehicleType.truck,
        );
        if (picked.storeName == '백반') {
          baekbanCount++;
        }
      }

      // 기대 비율 ≈ 3.0/(3.0+0.7) ≈ 81%. 여유를 두고 65% 이상 검증.
      expect(
        baekbanCount / draws,
        greaterThan(0.65),
        reason: '600회 중 백반 선택 $baekbanCount회',
      );
      // 라면도 최소한은 선택된다(0이 아님).
      expect(baekbanCount, lessThan(draws));
    });

    test('같은 차 승객들이 서로 다른 매장으로 흩어진다 (시뮬레이션 fast-forward)', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      expect(game.debugBuild('국밥'), isTrue);
      final anchors = game.debugPlacedTiles.entries
          .where((entry) => entry.value.showLabel)
          .map((entry) => entry.key)
          .toSet();
      expect(anchors.length, 2);

      // 최대 5게임일 fast-forward하며, 스폰된 보행자들이 고른 매장 앵커를
      // 누적 수집한다. 개인별 무작위 선택이므로 두 앵커가 모두 나와야 한다.
      final seenAnchors = <int>{};
      for (var i = 0; i < 3600 && seenAnchors.length < 2; i++) {
        game.update(0.5);
        for (final person in game.debugPeople) {
          final target = person.targetStoreAnchorTileNumber;
          if (target != null) {
            seenAnchors.add(target);
          }
        }
      }

      expect(
        seenAnchors,
        anchors,
        reason: '5게임일 동안 방문객이 두 매장 모두를 선택하지 않았습니다',
      );
    });
  });
}
