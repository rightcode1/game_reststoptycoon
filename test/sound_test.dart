import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reststop_tycoon/core/save.dart';
import 'package:reststop_tycoon/core/sound.dart';
import 'package:reststop_tycoon/game/highway_tycoon_game.dart';

/// 재생 호출을 기록하는 테스트용 구현체.
class RecordingSoundPlayer implements SoundPlayer {
  final List<GameSound> played = [];

  @override
  void play(GameSound sound) => played.add(sound);
}

int storeAnchorOf(HighwayTycoonGame game, String name) {
  return game.debugPlacedTiles.entries
      .firstWhere((entry) => entry.value.showLabel && entry.value.label == name)
      .key;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(HighwayTycoonGame, RecordingSoundPlayer)> createGame() async {
    SharedPreferences.setMockInitialValues({});
    final recorder = RecordingSoundPlayer();
    final game = HighwayTycoonGame(soundPlayer: recorder);
    await game.onLoad();
    return (game, recorder);
  }

  group('사운드 훅', () {
    test('모든 GameSound는 에셋 경로를 가진다 (플레이스홀더 단계)', () {
      for (final sound in GameSound.values) {
        expect(sound.assetPath, startsWith('assets/sounds/'));
      }
    });

    test('건설 성공 시 build, 첫 퀘스트 완료로 questComplete가 재생된다', () async {
      final (game, recorder) = await createGame();

      expect(game.debugBuild('라면'), isTrue);

      expect(recorder.played, contains(GameSound.build));
      expect(recorder.played, contains(GameSound.questComplete));
    });

    test('잔액 부족 건설 시 error가 재생된다', () async {
      final (game, recorder) = await createGame();
      game.debugMoney = 0;

      expect(game.debugBuild('라면'), isFalse);

      expect(recorder.played, [GameSound.error]);
    });

    test('구매 시 sale이 재생된다', () async {
      final (game, recorder) = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      recorder.played.clear();

      game.debugRecordSaleAt(storeAnchorOf(game, '라면'));

      expect(recorder.played, contains(GameSound.sale));
    });

    test('업그레이드·직원 고용 시 각각의 사운드가 재생된다', () async {
      final (game, recorder) = await createGame();
      expect(game.debugBuild('라면'), isTrue);
      final anchor = storeAnchorOf(game, '라면');
      recorder.played.clear();

      game.upgradeStore(anchor);
      game.hireStaff(anchor);

      expect(recorder.played, contains(GameSound.upgrade));
      expect(recorder.played, contains(GameSound.hireStaff));
    });

    test('오프라인 정산 시 offlineEarnings가 재생된다', () async {
      SharedPreferences.setMockInitialValues({});
      final fixedNow = DateTime(2026, 7, 9, 12);
      await SaveRepository().save(
        GameSaveData(
          money: 1000,
          elapsedGameMinutes: 50000,
          placedTiles: const [
            PlacedTileSave(tileNumber: 2147, label: '라면', showLabel: true),
          ],
          savedAtEpochMs: fixedNow
              .subtract(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        ),
      );
      final recorder = RecordingSoundPlayer();
      final game = HighwayTycoonGame(
        clock: () => fixedNow,
        soundPlayer: recorder,
      );
      await game.onLoad();

      expect(recorder.played, contains(GameSound.offlineEarnings));
    });

    test('차량이 주차하면 vehicleArrive가 재생된다 (시뮬레이션 fast-forward)', () async {
      final (game, recorder) = await createGame();

      // 최대 3게임일 fast-forward하며 첫 주차를 기다린다.
      for (var i = 0;
          i < 2160 && !recorder.played.contains(GameSound.vehicleArrive);
          i++) {
        game.update(0.5);
      }

      expect(recorder.played, contains(GameSound.vehicleArrive));
    });
  });
}
