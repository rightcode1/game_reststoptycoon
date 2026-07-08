import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:reststop_tycoon/app.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

/// 실제 앱을 시뮬레이터에서 구동해 핵심 유저 플로우를 검증하는 스모크 테스트.
/// 실행: fvm flutter test integration_test/smoke_test.dart -d <시뮬레이터 UDID>
///
/// 주의: Flame 게임 루프가 매 프레임 새 프레임을 스케줄하므로
/// pumpAndSettle()은 영원히 끝나지 않는다. 고정 시간 pump()만 사용할 것.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('건설 → 라면 선택 → 맵 배치 → 매출 차감', (tester) async {
    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));

    // 초기 HUD: 시작 자금 20,000원과 건설 버튼
    expect(find.text('매출 20,000원'), findsOneWidget);
    expect(find.text('건설'), findsOneWidget);

    // 건설 화면 진입
    await tester.tap(find.text('건설'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('식당'), findsOneWidget);

    // 첫 탭: 미리보기(설명 시트) / 둘째 탭: 선택 확정 → 맵으로 복귀
    final ramenTile = find.descendant(
      of: find.byType(GridView),
      matching: find.text('라면'),
    );
    await tester.tap(ramenTile);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(ramenTile);
    await tester.pump(const Duration(milliseconds: 800));

    // 맵 복귀 후, 배치 하이라이트(카메라 중앙 = 초기 타일 2147)를 탭해 건설
    expect(find.text('건설'), findsOneWidget);
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 500));

    // 라면 건설비 500원 차감 확인
    expect(find.text('매출 19,500원'), findsOneWidget);
  });
}
