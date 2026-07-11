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

  group('매장 접근성', () {
    test('보통 배치된 매장은 도달 가능하고 고립 집합이 비어 있다', () async {
      final game = await newGame();
      expect(game.debugBuild('라면'), isTrue);
      expect(game.debugBuild('국밥'), isTrue);
      for (final entry in game.debugPlacedTiles.entries) {
        if (entry.value.showLabel) {
          expect(game.debugIsStoreReachable(entry.key), isTrue);
        }
      }
      expect(game.debugUnreachableStoreAnchors, isEmpty);
    });

    test('매장이 아닌(빈) 타일은 도달성 판정이 false다', () async {
      final game = await newGame();
      expect(game.debugIsStoreReachable(2147), isFalse);
    });

    test('밀집 배치는 고립 매장을 만들고, 집합이 실제 도달성과 일치한다', () async {
      final game = await newGame();
      game.debugUnlockAllPlots();
      game.debugMoney = 100000000;
      for (var i = 0; i < 40; i++) {
        game.debugBuild('라면');
      }

      expect(game.debugUnreachableStoreAnchors, isNotEmpty,
          reason: '밀집 배치했는데 고립 매장이 감지되지 않았다');
      // 집합이 실제 도달성과 정확히 일치해야 한다.
      for (final entry in game.debugPlacedTiles.entries) {
        if (!entry.value.showLabel) {
          continue;
        }
        final flaggedUnreachable =
            game.debugUnreachableStoreAnchors.contains(entry.key);
        expect(flaggedUnreachable, !game.debugIsStoreReachable(entry.key));
      }
    });

    test('고립될 자리에 매장을 지으면 경고 notice가 뜬다', () async {
      final game = await newGame();
      game.debugUnlockAllPlots();
      game.debugMoney = 100000000;
      var warned = false;
      for (var i = 0; i < 40; i++) {
        game.debugBuild('라면');
        if (game.notice.value == '⚠ 이 매장은 손님이 닿지 못합니다 — 통로를 확보하세요') {
          warned = true;
        }
      }
      expect(warned, isTrue);
    });
  });
}
