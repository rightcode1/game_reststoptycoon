import 'package:flame/game.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:reststop_tycoon/app.dart';
import 'package:reststop_tycoon/core/save.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

/// 실제 앱을 시뮬레이터에서 구동해 핵심 유저 플로우를 검증하는 스모크 테스트.
/// 실행: fvm flutter test integration_test/smoke_test.dart -d <시뮬레이터 UDID>
///
/// 주의: Flame 게임 루프가 매 프레임 새 프레임을 스케줄하므로
/// pumpAndSettle()은 영원히 끝나지 않는다. 고정 시간 pump()만 사용할 것.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 최초 실행 튜토리얼(3장)을 넘긴다. 저장을 비운 시나리오는 전부 필요.
  Future<void> dismissTutorial(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('다음'));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.tap(find.text('시작하기'));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('최초 실행 → 튜토리얼 3장 → 완료 후 재실행 시 생략', (tester) async {
    await SaveRepository().clear();

    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));

    // 1장: 환영 → 2장 → 3장 → 시작하기
    expect(find.textContaining('환영합니다'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('건설하기'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('키우기'), findsOneWidget);
    await tester.tap(find.text('시작하기'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('환영합니다'), findsNothing);

    // 완료 플래그가 저장돼 재실행(새 위젯 트리)에서는 뜨지 않는다.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('환영합니다'), findsNothing);
    expect(find.text('건설'), findsOneWidget);
  });

  testWidgets('건설 → 라면 선택 → 맵 배치 → 매출 차감', (tester) async {
    // 이전 실행에서 저장된 게임이 복원되면 초기 자금 검증이 깨지므로 먼저 비운다.
    await SaveRepository().clear();

    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));
    await dismissTutorial(tester);

    // 초기 HUD: 시작 자금 20,000원, 건설 버튼, 첫 퀘스트 배너
    expect(find.text('자금 20,000원'), findsOneWidget);
    expect(find.text('건설'), findsOneWidget);
    expect(find.textContaining('첫 매장을 건설하세요'), findsOneWidget);

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

    // 맵 복귀 후 배치 모드: 하단 버튼이 '라면 배치 취소'로 바뀐다
    expect(find.text('라면 배치 취소'), findsOneWidget);
    // 배치 하이라이트(카메라 중앙 = 초기 타일 2147)를 탭해 건설
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 500));

    // 라면 건설비 500원 차감 + 첫 매장 퀘스트 보상 400원 = 19,900원.
    // 배치 모드 종료(건설 버튼 복귀)와 다음 퀘스트 배너도 확인.
    expect(find.text('자금 19,900원'), findsOneWidget);
    expect(find.text('건설'), findsOneWidget);
    expect(find.textContaining('5번 판매하세요'), findsOneWidget);
  });

  testWidgets('배치 취소 → 카페/디저트(핫도그) 건설 → 비용 차감', (tester) async {
    await SaveRepository().clear();

    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));
    await dismissTutorial(tester);
    expect(find.text('자금 20,000원'), findsOneWidget);

    Future<void> selectHotdog() async {
      await tester.tap(find.text('건설'));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.tap(find.text('카페/디저트'));
      await tester.pump(const Duration(milliseconds: 400));
      final hotdogTile = find.descendant(
        of: find.byType(GridView),
        matching: find.text('핫도그'),
      );
      await tester.tap(hotdogTile);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(hotdogTile);
      await tester.pump(const Duration(milliseconds: 800));
    }

    // 배치 모드 진입 후 취소: 돈 변화 없이 건설 버튼으로 복귀
    await selectHotdog();
    expect(find.text('핫도그 배치 취소'), findsOneWidget);
    await tester.tap(find.text('핫도그 배치 취소'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('건설'), findsOneWidget);
    expect(find.text('자금 20,000원'), findsOneWidget);

    // 다시 선택해 실제 배치: 핫도그 300원 차감 + 첫 매장 퀘스트 보상 400원
    await selectHotdog();
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('자금 20,100원'), findsOneWidget);
  });

  testWidgets('특수시설(주차) 건설 → 주차 슬롯 확장', (tester) async {
    await SaveRepository().clear();

    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));
    await dismissTutorial(tester);
    expect(find.text('자금 20,000원'), findsOneWidget);

    await tester.tap(find.text('건설'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.text('특수시설'));
    await tester.pump(const Duration(milliseconds: 400));
    final parkingTile = find.descendant(
      of: find.byType(GridView),
      matching: find.text('주차'),
    );
    await tester.tap(parkingTile);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(parkingTile);
    await tester.pump(const Duration(milliseconds: 800));

    // 주차 배치 타일은 카메라 중앙에서 떨어진 주차 존에 있으므로
    // 게임이 알려주는 하이라이트 좌표를 직접 탭한다.
    final game = tester
        .widget<GameWidget<HighwayTycoonGame>>(
          find.byType(GameWidget<HighwayTycoonGame>),
        )
        .game!;
    final tapPoint = game.debugPlacementScreenPoint();
    expect(tapPoint, isNotNull);
    await tester.tapAt(tapPoint!);
    await tester.pump(const Duration(milliseconds: 500));

    // 주차 건설비 200원 차감 + 슬롯이 2개 → 3개로 확장
    expect(find.text('자금 19,800원'), findsOneWidget);
    expect(game.debugParkingSlots.length, 3);
  });

  testWidgets('배치된 매장 탭 → 업그레이드 → 비용 차감', (tester) async {
    await SaveRepository().clear();

    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));
    await dismissTutorial(tester);

    // 라면 건설 (시나리오 1과 동일한 흐름)
    await tester.tap(find.text('건설'));
    await tester.pump(const Duration(milliseconds: 800));
    final ramenTile = find.descendant(
      of: find.byType(GridView),
      matching: find.text('라면'),
    );
    await tester.tap(ramenTile);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(ramenTile);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('자금 19,900원'), findsOneWidget);

    // 방금 배치한 매장(카메라 중앙)을 탭 → 업그레이드 다이얼로그
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('라면 Lv.1'), findsOneWidget);
    await tester.tap(find.text('업그레이드'));
    await tester.pump(const Duration(milliseconds: 600));

    // 업그레이드 비용 300원 차감 (500×0.6×Lv1)
    expect(find.text('자금 19,600원'), findsOneWidget);
  });

  testWidgets('부재 후 재접속 → 오프라인 수익 다이얼로그', (tester) async {
    // 2시간 전에 저장된 게임(라면 매장 1곳)을 심어둔다.
    await SaveRepository().save(
      GameSaveData(
        money: 1000,
        elapsedGameMinutes: 50000,
        placedTiles: const [
          PlacedTileSave(tileNumber: 2147, label: '라면', showLabel: true),
        ],
        savedAtEpochMs: DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      ),
    );

    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));

    // 2시간 = 20게임일 → 라면 Lv.1: 45원 × 5건 × 20일 ≈ 4,500원
    expect(find.text('부재 중 수익'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('부재 중 수익'), findsNothing);

    final game = tester
        .widget<GameWidget<HighwayTycoonGame>>(
          find.byType(GameWidget<HighwayTycoonGame>),
        )
        .game!;
    // 로드까지의 지연(수 초)만큼 금액이 미세하게 늘 수 있어 범위로 검증한다.
    expect(game.debugMoney, greaterThanOrEqualTo(1000 + 4500));
    expect(game.debugMoney, lessThan(1000 + 4650));
  });

  testWidgets('매장 관리 다이얼로그에서 직원 고용 → 비용 차감', (tester) async {
    await SaveRepository().clear();

    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));
    await dismissTutorial(tester);

    // 라면 건설
    await tester.tap(find.text('건설'));
    await tester.pump(const Duration(milliseconds: 800));
    final ramenTile = find.descendant(
      of: find.byType(GridView),
      matching: find.text('라면'),
    );
    await tester.tap(ramenTile);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(ramenTile);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('자금 19,900원'), findsOneWidget);

    // 매장 탭 → 다이얼로그에서 직원 고용 (1명째 = 500×0.4 = 200원)
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('직원: 0/'), findsOneWidget);
    await tester.tap(find.textContaining('직원 고용'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('자금 19,700원'), findsOneWidget);

    // 다시 열면 직원 1명 반영
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.textContaining('직원: 1/'), findsOneWidget);
  });

  testWidgets('설정 → 데이터 초기화 → 새 게임 + 튜토리얼 재표시', (tester) async {
    await SaveRepository().clear();

    await tester.pumpWidget(const RestStopTycoonApp());
    await tester.pump(const Duration(seconds: 1));
    await dismissTutorial(tester);

    // 라면 건설로 진행 상황을 만든다 (자금 19,900원)
    await tester.tap(find.text('건설'));
    await tester.pump(const Duration(milliseconds: 800));
    final ramenTile = find.descendant(
      of: find.byType(GridView),
      matching: find.text('라면'),
    );
    await tester.tap(ramenTile);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(ramenTile);
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byType(GameWidget<HighwayTycoonGame>));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('자금 19,900원'), findsOneWidget);

    // 설정 열기 → 데이터 초기화 → 확인
    await tester.tap(find.byIcon(Icons.settings));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('설정'), findsOneWidget);
    await tester.tap(find.text('데이터 초기화'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('정말 초기화할까요?'), findsOneWidget);
    await tester.tap(find.text('초기화'));
    await tester.pump(const Duration(milliseconds: 800));

    // 새 게임 상태 + 튜토리얼 재표시
    expect(find.text('자금 20,000원'), findsOneWidget);
    expect(find.textContaining('환영합니다'), findsOneWidget);
    await dismissTutorial(tester);
    expect(find.textContaining('첫 매장을 건설하세요'), findsOneWidget);
  });
}
