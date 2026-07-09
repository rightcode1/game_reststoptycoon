import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/save.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('튜토리얼 노출 조건', () {
    test('저장이 없는 최초 실행에는 튜토리얼을 요청한다', () async {
      SharedPreferences.setMockInitialValues({});
      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.tutorialRequested.value, isTrue);
    });

    test('완료하면 저장되고 다음 실행에는 요청하지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final firstRun = HighwayTycoonGame();
      await firstRun.onLoad();
      expect(firstRun.tutorialRequested.value, isTrue);

      firstRun.completeTutorial();
      // completeTutorial의 저장이 끝나길 기다린다.
      await Future<void>.delayed(Duration.zero);
      expect((await SaveRepository().load())!.tutorialSeen, isTrue);

      final secondRun = HighwayTycoonGame();
      await secondRun.onLoad();
      expect(secondRun.tutorialRequested.value, isFalse);
    });

    test('완료 전에 종료(자동 저장)했다면 다음 실행에 다시 요청한다', () async {
      SharedPreferences.setMockInitialValues({});
      final firstRun = HighwayTycoonGame();
      await firstRun.onLoad();
      await firstRun.saveNow(); // 튜토리얼 미완료 상태로 자동 저장

      final secondRun = HighwayTycoonGame();
      await secondRun.onLoad();

      expect(secondRun.tutorialRequested.value, isTrue);
    });

    test('tutorialSeen 필드가 없는 v5 이하 저장(기존 유저)은 생략한다', () async {
      SharedPreferences.setMockInitialValues({
        SaveRepository.storageKey:
            '{"version":5,"money":777,"elapsedGameMinutes":50000,'
                '"placedTiles":[]}',
      });

      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.tutorialRequested.value, isFalse);
    });
  });
}
