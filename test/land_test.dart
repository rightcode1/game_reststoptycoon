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
