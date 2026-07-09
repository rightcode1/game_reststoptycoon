import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/core/quests.dart';
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
    await game.onLoad();
    return game;
  }

  group('퀘스트 라인 정합성', () {
    test('모든 퀘스트는 양수 목표·보상과 설명을 가진다', () {
      expect(questLine, isNotEmpty);
      for (final quest in questLine) {
        expect(quest.description, isNotEmpty);
        expect(quest.target, greaterThan(0));
        expect(quest.reward, greaterThan(0));
      }
    });
  });

  group('퀘스트 진행', () {
    test('새 게임은 첫 퀘스트 배너를 보여준다', () async {
      final game = await createGame();

      expect(game.debugQuestIndex, 0);
      expect(game.questLabel.value, contains(questLine.first.description));
      expect(game.questLabel.value, contains('(0/1)'));
    });

    test('첫 매장 건설 시 퀘스트 완료 → 보상 지급 + 다음 퀘스트로', () async {
      final game = await createGame();

      expect(game.debugBuild('라면'), isTrue);

      expect(game.debugQuestIndex, 1);
      expect(
        game.debugMoney,
        Balance.startingMoney -
            Balance.buildCostOf('라면')! +
            questLine[0].reward,
      );
      expect(game.notice.value, contains('퀘스트 완료'));
      expect(game.questLabel.value, contains(questLine[1].description));
    });

    test('판매 퀘스트 진행도가 배너에 반영되고 달성 시 보상이 지급된다', () async {
      final game = await createGame();
      expect(game.debugBuild('라면'), isTrue); // 퀘스트 1 완료 → 판매 퀘스트로
      final anchor = storeAnchorOf(game, '라면');

      game.debugRecordSaleAt(anchor);
      game.debugRecordSaleAt(anchor);
      expect(game.questLabel.value, contains('(2/5)'));

      final before = game.debugMoney;
      final salePrice = Balance.salePriceWith('라면', 1, 0)!;
      game.debugRecordSaleAt(anchor);
      game.debugRecordSaleAt(anchor);
      game.debugRecordSaleAt(anchor); // 5번째 판매 → 퀘스트 2 완료

      expect(game.debugQuestIndex, 2);
      expect(game.debugMoney, before + salePrice * 3 + questLine[1].reward);
      expect(game.questLabel.value, contains(questLine[2].description));
      // 매장 3곳 목표: 이미 1곳 지었으므로 (1/3)
      expect(game.questLabel.value, contains('(1/3)'));
    });
  });

  group('퀘스트 저장/복원', () {
    test('퀘스트 인덱스와 누적 지표가 저장·복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final firstRun = HighwayTycoonGame();
      await firstRun.onLoad();
      expect(firstRun.debugBuild('라면'), isTrue);
      firstRun.debugRecordSaleAt(storeAnchorOf(firstRun, '라면'));
      await firstRun.saveNow();

      final secondRun = HighwayTycoonGame();
      await secondRun.onLoad();

      expect(secondRun.debugQuestIndex, 1);
      expect(secondRun.debugQuestStats[QuestMetric.storesBuilt], 1);
      expect(secondRun.debugQuestStats[QuestMetric.salesCount], 1);
      expect(secondRun.questLabel.value, contains('(1/5)'));
    });

    test('퀘스트 필드가 없는 v4 이하 저장은 처음부터 시작한다', () async {
      SharedPreferences.setMockInitialValues({
        SaveRepository.storageKey:
            '{"version":4,"money":777,"elapsedGameMinutes":50000,'
                '"placedTiles":[]}',
      });

      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.debugQuestIndex, 0);
      expect(game.questLabel.value, contains(questLine.first.description));
    });

    test('모든 퀘스트를 끝낸 저장은 배너를 숨긴다', () async {
      SharedPreferences.setMockInitialValues({});
      await SaveRepository().save(
        GameSaveData(
          money: 777,
          elapsedGameMinutes: 50000,
          placedTiles: const [],
          questIndex: questLine.length,
        ),
      );

      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.questLabel.value, isNull);
    });
  });
}
