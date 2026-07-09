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
  });
}
