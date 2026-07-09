import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/quests.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

/// 경제 건전성 계측: 표준 배치에서 fast-forward로 실측한 판매량이
/// 최소 기준을 유지하는지 검증한다. 시뮬레이션(교통/보행/구매) 어딘가가
/// 망가져 손님이 끊기면 이 테스트가 잡아낸다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('표준 배치(매장 2 + 주차 1)에서 3게임일 판매량 계측', () async {
    SharedPreferences.setMockInitialValues({});
    final game = HighwayTycoonGame();
    await game.onLoad();
    expect(game.debugBuild('라면'), isTrue);
    expect(game.debugBuild('국밥'), isTrue);
    expect(game.debugBuild('주차'), isTrue); // 슬롯 3개

    final salesBefore = game.debugQuestStats[QuestMetric.salesCount]!;
    final moneyBefore = game.debugMoney;

    // 3게임일 = 4,320게임분 = 현실 1,080초 → 0.5초 스텝 2,160회
    for (var i = 0; i < 2160; i++) {
      game.update(0.5);
    }

    final sales =
        game.debugQuestStats[QuestMetric.salesCount]! - salesBefore;
    final moneyDelta = game.debugMoney - moneyBefore;
    // ignore: avoid_print
    print('[계측] 3게임일 판매 $sales건 (일평균 ${(sales / 3).toStringAsFixed(1)}건), '
        '자금 변화 +$moneyDelta원');

    // 시뮬레이션 건전성 하한: 하루 평균 몇 건이라도 꾸준히 팔려야 한다.
    expect(sales, greaterThan(15), reason: '3게임일 판매가 비정상적으로 적습니다');
  });
}
