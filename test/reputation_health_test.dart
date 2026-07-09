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
}
