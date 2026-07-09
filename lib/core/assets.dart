/// 에셋 경로 상수 모음.
///
/// 실제 에셋로 교체할 때 이 파일의 경로만 갱신하면 되도록
/// 모든 에셋 참조를 여기에 모은다.
library;

abstract final class GameAssets {
  // ---- 사운드 ----
  // TODO(ASSET): 사운드 파일 전부 미보유. 짧은 SFX(1초 내외), wav 또는 mp3.
  // 파일을 assets/sounds/에 넣고 pubspec.yaml에 디렉터리를 등록한 뒤
  // SilentSoundPlayer를 오디오 구현체로 교체할 것 (lib/core/sound.dart 참조).
  static const String soundBuild = 'assets/sounds/build.wav';
  static const String soundUpgrade = 'assets/sounds/upgrade.wav';
  static const String soundHireStaff = 'assets/sounds/hire_staff.wav';
  static const String soundSale = 'assets/sounds/sale.wav';
  static const String soundQuestComplete = 'assets/sounds/quest_complete.wav';
  static const String soundOfflineEarnings =
      'assets/sounds/offline_earnings.wav';
  static const String soundError = 'assets/sounds/error.wav';
  static const String soundVehicleArrive = 'assets/sounds/vehicle_arrive.wav';

  // ---- 이미지 ----
  // TODO(ASSET): pubspec에 등록돼 있으나 아직 코드에서 사용하지 않는다.
  // 차량/보행자/타일 스프라이트 적용 시 여기서 경로를 관리할 것.
  static const String vehiclesDir = 'assets/images/vehicles/';
  static const String floorDir = 'assets/images/floor/';
  static const String conceptReference = 'assets/reference/concept.png';
}
