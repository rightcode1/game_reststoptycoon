import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/balance.dart';
import 'package:reststop_tycoon/core/quests.dart';
import 'package:reststop_tycoon/core/save.dart';
import 'package:reststop_tycoon/core/settings.dart';
import 'package:reststop_tycoon/core/sound.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

class RecordingSoundPlayer implements SoundPlayer {
  final List<GameSound> played = [];

  @override
  void play(GameSound sound) => played.add(sound);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsRepository', () {
    test('기본값은 사운드 켜짐이고 저장·복원된다', () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SettingsRepository();

      expect(await repository.loadSoundEnabled(), isTrue);

      await repository.saveSoundEnabled(false);
      expect(await repository.loadSoundEnabled(), isFalse);
    });
  });

  group('사운드 토글', () {
    test('사운드를 끄면 훅이 무시되고, 설정이 저장된다', () async {
      SharedPreferences.setMockInitialValues({});
      final recorder = RecordingSoundPlayer();
      final game = HighwayTycoonGame(soundPlayer: recorder);
      await game.onLoad();

      game.setSoundEnabled(false);
      expect(game.debugBuild('라면'), isTrue);
      expect(recorder.played, isEmpty);

      game.setSoundEnabled(true);
      game.debugMoney = 0;
      expect(game.debugBuild('국밥'), isFalse);
      expect(recorder.played, [GameSound.error]);

      // 설정은 진행 저장과 별도 키에 저장된다.
      expect(await SettingsRepository().loadSoundEnabled(), isTrue);
    });

    test('꺼진 설정은 다음 실행에서 복원된다', () async {
      SharedPreferences.setMockInitialValues({
        SettingsRepository.soundEnabledKey: false,
      });
      final game = HighwayTycoonGame();
      await game.onLoad();

      expect(game.soundEnabled.value, isFalse);
    });
  });

  group('데이터 초기화', () {
    test('진행 상황이 전부 초기 상태로 돌아가고 저장이 삭제된다', () async {
      SharedPreferences.setMockInitialValues({});
      final game = HighwayTycoonGame();
      await game.onLoad();
      expect(game.debugBuild('라면'), isTrue);
      expect(game.debugBuild('주차'), isTrue);
      game.upgradeStore(
        game.debugPlacedTiles.entries
            .firstWhere((entry) => entry.value.label == '라면')
            .key,
      );
      await game.saveNow();

      await game.resetGame();

      expect(game.debugMoney, Balance.startingMoney);
      expect(game.moneyLabel.value, '자금 20,000원');
      expect(game.debugPlacedTiles, isEmpty);
      expect(game.debugParkingSlots.length, 2); // 기본 슬롯만
      expect(game.debugQuestIndex, 0);
      expect(game.debugQuestStats[QuestMetric.storesBuilt], 0);
      expect(game.questLabel.value, contains('첫 매장'));
      expect(game.tutorialRequested.value, isTrue);
      expect(await SaveRepository().load(), isNull);
    });

    test('초기화해도 사운드 설정은 유지된다', () async {
      SharedPreferences.setMockInitialValues({});
      final game = HighwayTycoonGame();
      await game.onLoad();
      game.setSoundEnabled(false);
      await Future<void>.delayed(Duration.zero);

      await game.resetGame();

      expect(game.soundEnabled.value, isFalse);
      expect(await SettingsRepository().loadSoundEnabled(), isFalse);
    });
  });
}
