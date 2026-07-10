import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<HighwayTycoonGame> newGame() async {
    SharedPreferences.setMockInitialValues({});
    final game = HighwayTycoonGame();
    await game.onLoad();
    return game;
  }

  group('나무 치우기', () {
    test('해금된 부지에 치울 수 있는 나무가 있다', () async {
      final game = await newGame();
      game.debugUnlockAllPlots();
      expect(game.debugFirstClearableTree(), isNotNull);
    });

    test('나무를 치우면 비용이 차감되고 그 타일이 더 이상 나무가 아니다', () async {
      final game = await newGame();
      game.debugUnlockAllPlots();
      game.debugMoney = 100000;
      final tree = game.debugFirstClearableTree()!;
      expect(game.debugIsTree(tree), isTrue);
      final money = game.debugMoney;
      expect(game.clearTree(tree), isTrue);
      expect(game.debugIsTree(tree), isFalse);
      expect(game.debugMoney, money - Balance.treeClearCost);
    });

    test('잔액이 부족하면 나무를 못 치운다', () async {
      final game = await newGame();
      game.debugUnlockAllPlots();
      game.debugMoney = 0;
      final tree = game.debugFirstClearableTree()!;
      expect(game.clearTree(tree), isFalse);
      expect(game.debugIsTree(tree), isTrue);
    });

    test('나무가 아닌 타일은 clearTree가 false다', () async {
      final game = await newGame();
      game.debugUnlockAllPlots();
      game.debugMoney = 100000;
      expect(game.clearTree(2147), isFalse); // 2147은 시작 상업 타일
    });

    test('치운 나무는 저장·복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final game = HighwayTycoonGame();
      await game.onLoad();
      game.debugUnlockAllPlots();
      game.debugMoney = 100000;
      final tree = game.debugFirstClearableTree()!;
      game.clearTree(tree);
      await game.saveNow();

      final reloaded = HighwayTycoonGame();
      await reloaded.onLoad();
      expect(reloaded.debugIsTree(tree), isFalse);
    });
  });
}
