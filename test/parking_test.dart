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

  group('주차 슬롯 확장', () {
    test('기본 주차 슬롯은 2개다', () async {
      final game = await createGame();

      expect(game.debugParkingSlots.length, 2);
    });

    test('주차 배치 시 실제 슬롯이 등록되고 건설비가 차감된다', () async {
      final game = await createGame();

      expect(game.debugBuild('주차'), isTrue);

      expect(game.debugParkingSlots.length, 3);
      expect(game.debugMoney, Balance.startingMoney - Balance.buildCostOf('주차')!);

      // 새 슬롯의 위치는 배치된 타일과 일치한다.
      final placedParkingTile = game.debugPlacedTiles.entries
          .firstWhere((entry) => entry.value.label == '주차')
          .key;
      expect(game.debugParkingSlots.last.spotTileNumber, placedParkingTile);
    });

    test('새 슬롯에 대해 진입·출차 경로가 생성된다', () async {
      final game = await createGame();
      expect(game.debugBuild('주차'), isTrue);
      final newSlot = game.debugParkingSlots.last;

      final arrival = game.debugArrivalRouteFor(newSlot);
      expect(arrival.length, greaterThanOrEqualTo(7)); // 스폰~분기점 6 + 슬롯까지
      expect(arrival.last, game.debugTileCenter(newSlot.spotTileNumber));

      final exit = game.debugExitRouteFor(newSlot);
      expect(exit.length, greaterThanOrEqualTo(3));
      expect(exit.last, game.debugTileCenter(2000)); // 맵 밖 출구 타일
    });

    test('기본 슬롯이 차면 확장 슬롯에도 차량이 주차한다', () async {
      final game = await createGame();
      expect(game.debugBuild('주차'), isTrue);
      expect(game.debugBuild('주차'), isTrue);
      expect(game.debugBuild('주차'), isTrue);
      final dynamicSlots = game.debugParkingSlots.sublist(2);

      // 최대 5게임일(현실 1,800초)을 0.5초 스텝으로 fast-forward하며
      // 확장 슬롯이 예약/점유되는 순간을 기다린다.
      var dynamicSlotUsed = false;
      for (var i = 0; i < 3600 && !dynamicSlotUsed; i++) {
        game.update(0.5);
        dynamicSlotUsed = dynamicSlots.any(
          (slot) => slot.occupiedBy != null || slot.reservedBy != null,
        );
      }

      expect(
        dynamicSlotUsed,
        isTrue,
        reason: '5게임일 동안 확장 주차 슬롯이 한 번도 사용되지 않았습니다',
      );
    });

    test('여러 개를 연달아 지어도 각각 슬롯이 등록된다', () async {
      final game = await createGame();

      expect(game.debugBuild('주차'), isTrue);
      expect(game.debugBuild('주차'), isTrue);
      expect(game.debugBuild('주차'), isTrue);

      expect(game.debugParkingSlots.length, 5);
      // 슬롯 위치는 모두 서로 다르다.
      final spots =
          game.debugParkingSlots.map((slot) => slot.spotTileNumber).toSet();
      expect(spots.length, 5);
    });
  });

  group('주차 배치 제한', () {
    test('차량 도로(코리도)·대기열 타일에는 배치할 수 없다', () async {
      final game = await createGame();

      // 분기점, 진입 코리도, 좌측 대기열, 스폰 타일
      for (final tileNumber in [2093, 2149, 2176, 2509]) {
        expect(
          game.debugBuildAt(tileNumber, '주차'),
          isFalse,
          reason: '도로 타일 $tileNumber에 주차가 배치되면 안 됩니다',
        );
      }
      expect(game.debugMoney, Balance.startingMoney);
      expect(game.debugParkingSlots.length, 2);
    });

    test('상업 존에는 배치할 수 없다', () async {
      final game = await createGame();
      // 2147은 초기 카메라 중앙의 상업 타일(식당 배치는 가능한 자리).
      expect(game.debugBuildAt(2147, '라면'), isTrue);
      final anotherGame = await createGame();

      expect(anotherGame.debugBuildAt(2147, '주차'), isFalse);
      expect(anotherGame.debugParkingSlots.length, 2);
    });
  });

  group('주차 슬롯 저장/복원', () {
    test('주차를 짓고 저장하면 새 게임 인스턴스에서 슬롯이 복원된다', () async {
      SharedPreferences.setMockInitialValues({});

      final firstRun = HighwayTycoonGame();
      await firstRun.onLoad();
      expect(firstRun.debugBuild('주차'), isTrue);
      final savedSpot = firstRun.debugParkingSlots.last.spotTileNumber;
      await firstRun.saveNow();

      final secondRun = HighwayTycoonGame();
      await secondRun.onLoad();

      expect(secondRun.debugParkingSlots.length, 3);
      expect(secondRun.debugParkingSlots.last.spotTileNumber, savedSpot);
    });
  });
}
