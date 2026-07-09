/// 게임 상태 저장/로드.
///
/// 영속화 대상은 플레이어 진행 상태(돈, 게임 시간, 배치 시설)뿐이다.
/// 차량/보행자 같은 순간적인 시뮬레이션 상태는 재시작 시 리셋된다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 배치된 타일 하나의 저장 형식.
class PlacedTileSave {
  const PlacedTileSave({
    required this.tileNumber,
    required this.label,
    required this.showLabel,
    this.level = 1,
    this.staffCount = 0,
  });

  factory PlacedTileSave.fromJson(Map<String, dynamic> json) {
    return PlacedTileSave(
      tileNumber: json['tileNumber'] as int,
      label: json['label'] as String,
      showLabel: json['showLabel'] as bool,
      // v1 저장에는 level이 없다 → 1로 마이그레이션.
      level: json['level'] as int? ?? 1,
      // v3 이하 저장에는 staffCount가 없다 → 0으로 마이그레이션.
      staffCount: json['staffCount'] as int? ?? 0,
    );
  }

  final int tileNumber;
  final String label;
  final bool showLabel;
  final int level;
  final int staffCount;

  Map<String, dynamic> toJson() => {
        'tileNumber': tileNumber,
        'label': label,
        'showLabel': showLabel,
        'level': level,
        'staffCount': staffCount,
      };
}

/// 저장 파일 전체 스키마. 필드 추가/변경 시 [currentVersion]을 올리고
/// 마이그레이션을 고려할 것.
class GameSaveData {
  const GameSaveData({
    this.version = currentVersion,
    required this.money,
    required this.elapsedGameMinutes,
    required this.placedTiles,
    this.savedAtEpochMs,
    this.questIndex = 0,
    this.questStats = const {},
    this.tutorialSeen = true,
  });

  factory GameSaveData.fromJson(Map<String, dynamic> json) {
    return GameSaveData(
      version: json['version'] as int,
      money: json['money'] as int,
      elapsedGameMinutes: (json['elapsedGameMinutes'] as num).toDouble(),
      placedTiles: (json['placedTiles'] as List<dynamic>)
          .map((item) => PlacedTileSave.fromJson(item as Map<String, dynamic>))
          .toList(),
      // v2 이하 저장에는 없다 → null이면 오프라인 정산을 건너뛴다.
      savedAtEpochMs: json['savedAtEpochMs'] as int?,
      // v4 이하 저장에는 퀘스트 데이터가 없다 → 처음부터 시작.
      questIndex: json['questIndex'] as int? ?? 0,
      questStats: (json['questStats'] as Map<String, dynamic>?)
              ?.map((key, value) => MapEntry(key, value as int)) ??
          const {},
      // v5 이하 저장(기존 유저)은 튜토리얼을 본 것으로 취급.
      tutorialSeen: json['tutorialSeen'] as bool? ?? true,
    );
  }

  /// v1 → v2: placedTiles에 level 추가 (없으면 1로 읽음).
  /// v2 → v3: savedAtEpochMs 추가 (없으면 오프라인 정산 생략).
  /// v3 → v4: placedTiles에 staffCount 추가 (없으면 0으로 읽음).
  /// v4 → v5: questIndex·questStats 추가 (없으면 0/빈 맵).
  /// v5 → v6: tutorialSeen 추가 (없으면 true — 기존 유저는 생략).
  static const int currentVersion = 6;

  final int version;
  final int money;
  final double elapsedGameMinutes;
  final List<PlacedTileSave> placedTiles;

  /// 저장 시각(현실 시간, epoch ms). 오프라인 수익 정산 기준.
  final int? savedAtEpochMs;

  /// 현재 진행 중인 퀘스트 인덱스(questLine 기준).
  final int questIndex;

  /// 퀘스트 누적 지표. 키는 QuestMetric.name.
  final Map<String, int> questStats;

  /// 튜토리얼 완료 여부.
  final bool tutorialSeen;

  Map<String, dynamic> toJson() => {
        'version': version,
        'money': money,
        'elapsedGameMinutes': elapsedGameMinutes,
        'placedTiles': placedTiles.map((tile) => tile.toJson()).toList(),
        if (savedAtEpochMs != null) 'savedAtEpochMs': savedAtEpochMs,
        'questIndex': questIndex,
        'questStats': questStats,
        'tutorialSeen': tutorialSeen,
      };
}

/// SharedPreferences에 JSON 문자열 하나로 저장하는 리포지토리.
class SaveRepository {
  static const String storageKey = 'reststop_tycoon_save';

  /// 저장된 게임을 읽는다. 저장이 없거나 데이터가 손상됐으면 null(새 게임).
  Future<GameSaveData?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return GameSaveData.fromJson(decoded);
    } catch (_) {
      // 손상된 저장 데이터는 버리고 새 게임으로 시작한다.
      return null;
    }
  }

  Future<void> save(GameSaveData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(data.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
