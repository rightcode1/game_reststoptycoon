/// 사운드 훅.
///
/// 게임 로직은 [SoundPlayer.play]만 호출하고 실제 재생은 구현체가 담당한다.
/// 현재는 오디오 에셋이 없어 [SilentSoundPlayer](무음)가 기본 구현이다.
///
/// TODO(ASSET): 사운드 파일 확보 후 오디오 패키지(audioplayers 등) 기반
/// 구현체를 추가하고, 각 [GameSound.assetPath]를 연결할 것.
/// 설정 화면의 사운드 토글도 이 인터페이스 뒤에서 처리하면 된다.
library;

import 'assets.dart';

/// 게임에서 발생하는 사운드 이벤트와 대응 에셋 경로.
enum GameSound {
  /// 시설 건설 완료.
  build(GameAssets.soundBuild),

  /// 매장 업그레이드 완료.
  upgrade(GameAssets.soundUpgrade),

  /// 직원 고용 완료.
  hireStaff(GameAssets.soundHireStaff),

  /// 방문객 구매(매출 발생).
  sale(GameAssets.soundSale),

  /// 퀘스트 달성.
  questComplete(GameAssets.soundQuestComplete),

  /// 재접속 부재 중 수익 정산.
  offlineEarnings(GameAssets.soundOfflineEarnings),

  /// 실패 피드백(잔액 부족, 배치 불가 등).
  error(GameAssets.soundError),

  /// 차량이 주차 슬롯에 도착.
  vehicleArrive(GameAssets.soundVehicleArrive);

  const GameSound(this.assetPath);

  /// 재생할 에셋 경로(아직 파일 없음 — 무음 플레이스홀더 단계).
  final String assetPath;
}

abstract class SoundPlayer {
  void play(GameSound sound);
}

/// 무음 플레이스홀더 구현. 오디오 에셋 확보 전까지의 기본값.
class SilentSoundPlayer implements SoundPlayer {
  @override
  void play(GameSound sound) {
    // 의도적으로 아무것도 하지 않는다.
  }
}
