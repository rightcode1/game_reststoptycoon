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

    test('잔액 부족 해금은 거부된다', () async {
      final game = await newGame();
      game.debugMoney = 0;
      final target = game.debugFirstAdjacentLockedPlot()!;
      expect(game.unlockPlot(target), isFalse);
    });

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
  });
}
