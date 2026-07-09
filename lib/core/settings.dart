/// 기기 설정 저장소.
///
/// 게임 진행(save.dart)과 별개의 키에 저장되므로
/// '데이터 초기화'를 해도 설정은 유지된다.
library;

import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const String soundEnabledKey = 'reststop_tycoon_sound_enabled';

  Future<bool> loadSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(soundEnabledKey) ?? true;
  }

  Future<void> saveSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(soundEnabledKey, enabled);
  }
}
