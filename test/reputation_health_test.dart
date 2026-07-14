import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

/// 정체 루프 건전성: 고수요·저용량으로 정체를 유발한 뒤 주차를 확장하면,
/// 교착(gridlock) 없이 흐름이 되살아나고 평판이 회복돼야 한다.
/// 차량이 공유 분기점에서 상호 영구 차단되면 이 테스트가 잡아낸다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('정체 → 주차 확장 시 교착 없이 흐름·평판이 회복된다', () async {
    SharedPreferences.setMockInitialValues({});
    final game = HighwayTycoonGame();
    await game.onLoad();
    game.debugMoney = 100000000;

    var stores = 0;
    for (final s in const ['돈까스', '제육볶음', '불고기', '백반', '설렁탕']) {
      if (game.debugBuild(s)) stores++;
    }

    const stepsPerDay = 720; // 1440게임분 ÷ (0.5초 × 4게임분/초)
    double runDay(String tag) {
      for (var i = 0; i < stepsPerDay; i++) {
        game.update(0.5);
      }
      // ignore: avoid_print
      print('[$tag] 평판=${game.debugReputation.toStringAsFixed(1)} '
          '차량=${game.debugVehicleCount} '
          '상태=${game.debugVehicleStateCounts}');
      return game.debugReputation;
    }

    final congestion = <double>[];
    for (var d = 0; d < 6; d++) {
      congestion.add(runDay('정체 D${d + 1}'));
    }

    var parking = 0;
    for (var i = 0; i < 4; i++) {
      if (game.debugBuild('주차')) parking++;
    }
    // ignore: avoid_print
    print('=== 주차 +$parking (총 ${game.debugParkingSlots.length}슬롯) ===');

    final recovery = <double>[];
    final vehicleCounts = <int>[];
    for (var d = 0; d < 8; d++) {
      recovery.add(runDay('회복 D${d + 1}'));
      vehicleCounts.add(game.debugVehicleCount);
    }

    // liveness: 회복 단계에서 차량 집합이 매일 완전히 동일하게 '동결'되면 교착이다.
    expect(
      vehicleCounts.toSet().length,
      greaterThan(1),
      reason: '차량 수가 동결됨 — 교착(gridlock) 발생: $vehicleCounts',
    );
    // 용량을 늘렸으면 평판이 정체 저점보다 회복해야 한다.
    final congestionMin = congestion.reduce((a, b) => a < b ? a : b);
    expect(
      recovery.last,
      greaterThan(congestionMin),
      reason: '주차 확장이 평판을 회복시키지 못함(교착) — '
          '정체저점=$congestionMin 회복끝=${recovery.last}',
    );
    expect(stores, 5);
  });

  // 프로비저닝 균형: 잘 갖추면 평판이 높게 유지되고(유입 보너스),
  // 과수요면 확실히 떨어지되 바닥(죽음의 나선) 없이 자기 교정된다.
  // 평판 상수(servedStep/lostStep/demandFactor)를 잘못 만지면 잡힌다.
  test('프로비저닝 격차: 균형은 높은 평판, 과수요는 낮지만 자기 교정된다', () async {
    Future<HighwayTycoonGame> setup(List<String> builds) async {
      SharedPreferences.setMockInitialValues({});
      final game = HighwayTycoonGame();
      await game.onLoad();
      game.debugMoney = 500000; // 배치 자금 분리(모든 건설 성공)
      for (final b in builds) {
        game.debugBuild(b);
      }
      return game;
    }

    (double, int) run8days(HighwayTycoonGame game) {
      for (var i = 0; i < 8 * 720; i++) {
        game.update(0.5);
      }
      return (game.debugReputation, game.debugSalesCount);
    }

    final balanced =
        await setup(['라면', '국밥', '돈까스', '주차', '주차', '주차']);
    final (balRep, _) = run8days(balanced);

    final over = await setup(['라면', '국밥', '돈까스', '백반', '제육볶음', '불고기']);
    final (overRep, overSales) = run8days(over);

    // ignore: avoid_print
    print('[프로비저닝] 균형 평판=${balRep.toStringAsFixed(1)}  '
        '과수요 평판=${overRep.toStringAsFixed(1)} 판매=$overSales');

    expect(balRep, greaterThan(68), reason: '과잉공급인데 평판이 낮다');
    expect(overRep, lessThan(55), reason: '과수요인데 평판이 안 떨어졌다');
    expect(overRep, greaterThan(12), reason: '과수요 평판이 바닥까지 붕괴했다');
    expect(overSales, greaterThan(30), reason: '과수요에서 판매가 끊겼다');
    expect(balRep - overRep, greaterThan(20), reason: '프로비저닝 격차가 미미하다');
  });
}
