import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../core/balance.dart';
import '../core/quests.dart';
import '../core/save.dart';
import '../core/settings.dart';
import '../core/sound.dart';

class HighwayTycoonGame extends FlameGame {
  HighwayTycoonGame({
    SaveRepository? saveRepository,
    SettingsRepository? settingsRepository,
    DateTime Function()? clock,
    SoundPlayer? soundPlayer,
  })  : _saveRepository = saveRepository ?? SaveRepository(),
        _settingsRepository = settingsRepository ?? SettingsRepository(),
        _now = clock ?? DateTime.now,
        _sound = soundPlayer ?? SilentSoundPlayer();

  static const int mapColumns = 50;
  static const int mapRows = 50;
  static const int parkingEndX = 25;
  static const int entryRoadLeftX = 24;
  static const int entryRoadRightX = 25;
  static const int entryRoadStartY = 51;
  static const int entryRoadEndY = 70;
  static const int spawnLeftTileNumber = 2509;
  static const int spawnRightTileNumber = 2517;
  static const int laneLeftTileNumber = 2518;
  static const int laneRightTileNumber = 2525;
  static const List<int> leftQueueTileNumbers = [2176, 2203, 2229, 2254];
  static const List<int> rightQueueTileNumbers = [2202, 2228, 2253, 2277];

  /// 모든 차량 진입 경로가 지나는 분기점 타일. 확장 주차 슬롯 경로는
  /// 여기서부터 BFS로 이어 붙인다.
  static const int parkingJunctionTileNumber = 2093;

  /// 출차 경로 합류점 타일(이후 2001 → 2000으로 맵을 빠져나간다).
  static const int exitJunctionTileNumber = 2033;

  /// 차량 도로로 쓰이는 타일들 — '주차' 시설을 배치할 수 없다.
  static const Set<int> vehicleCorridorTileNumbers = {
    spawnLeftTileNumber, spawnRightTileNumber,
    laneLeftTileNumber, laneRightTileNumber,
    2176, 2203, 2229, 2254, // 좌측 대기열
    2202, 2228, 2253, 2277, // 우측 대기열
    2175, 2149, 2122, 2093, 2063, 2064, 2033, 2001, 2000, // 진입/출차 코리도
  };
  static const double minZoom = 0.45;
  static const double maxZoom = 2.6;
  static const double tileHalfWidth = 42;
  static const double tileHalfHeight = 22;
  static const double cameraMargin = 80;
  static const double vehicleSpacing = 18;
  static const double pedestrianSideOffset = 8;
  static const double pedestrianSpawnJitter = 4;
  static const int realSecondsPerGameYear = 129600;
  static const int gameMinutesPerYear = 12 * 30 * 24 * 60;
  static const double gameMinutesPerRealSecond =
      gameMinutesPerYear / realSecondsPerGameYear;
  static const int startingGameMinutes = ((((1 * 30) + 1) * 24 + 12) * 60) + 30;
  static const int gameMinutesPerDay = 24 * 60;
  static const Set<int> restroomTileNumbers = {2173, 2199, 2200, 2226};
  static const Set<int> parkingLabelTileNumbers = {2092, 2121};
  static const Set<int> treeTileNumbers = {2201, 2227, 2252};

  final List<MapTile> _tiles = [];
  final Set<int> _treeTileNumbers = <int>{};
  final Map<int, PlacedTileData> _placedTiles = {};
  final Map<int, MapTile> _tileByNumber = {};
  final Map<(int, int), MapTile> _tileByCoordinate = {};
  final Map<String, _SpecialLabelPainters> _specialLabelPainterCache = {};
  final List<MovingVehicle> _vehicles = [];
  final List<WalkingPerson> _people = [];
  final List<FloatingSaleText> _floatingSaleTexts = [];

  /// 매출 플로팅 텍스트 수명(현실 초)과 상승 속도(월드 px/초).
  static const double floatingSaleLifetimeSeconds = 1.4;
  static const double floatingSaleRiseSpeed = 22;
  final List<DailyArrival> _dailyArrivals = [];
  final List<ParkingSlot> _parkingSlots = [
    ParkingSlot(spotTileNumber: 2092, approachTileNumber: 2063),
    ParkingSlot(spotTileNumber: 2121, approachTileNumber: 2093),
  ];
  final ValueNotifier<String> timeLabel = ValueNotifier<String>(
    _formatGameTime(startingGameMinutes),
  );
  final ValueNotifier<String> moneyLabel = ValueNotifier<String>(
    _formatMoney(Balance.startingMoney),
  );

  /// 화면에 잠깐 띄울 안내 메시지(스낵바용). UI가 소비한 뒤 null로 되돌린다.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  /// 배치 대기 중인 매장 이름. null이면 배치 모드가 아니다.
  final ValueNotifier<String?> pendingPlacementLabel =
      ValueNotifier<String?>(null);

  /// 배치된 매장 탭 시 발행되는 업그레이드 요청. UI가 소비 후 null로 되돌린다.
  final ValueNotifier<StoreUpgradeRequest?> upgradeRequest =
      ValueNotifier<StoreUpgradeRequest?>(null);

  /// 재접속 시 오프라인 정산 결과(다이얼로그용). UI가 소비 후 null로 되돌린다.
  final ValueNotifier<OfflineEarningsReport?> offlineEarnings =
      ValueNotifier<OfflineEarningsReport?>(null);

  /// HUD 퀘스트 배너 텍스트. 모든 퀘스트 완료 시 null.
  final ValueNotifier<String?> questLabel = ValueNotifier<String?>(null);

  /// 평판(0~100) — HUD 배지가 구독.
  final ValueNotifier<double> reputation =
      ValueNotifier<double>(Balance.reputationStart);

  /// 오늘 정체로 놓친 손님(차량) 수 — HUD 정체 경고가 구독.
  final ValueNotifier<int> congestion = ValueNotifier<int>(0);

  /// 잠긴 부지 탭 → UI 해금 다이얼로그 요청(플롯키·비용). 없으면 null.
  final ValueNotifier<LandUnlockRequest?> landUnlockRequest =
      ValueNotifier<LandUnlockRequest?>(null);

  /// 최초 실행(또는 튜토리얼 미완료) 시 true — UI가 튜토리얼을 띄운다.
  final ValueNotifier<bool> tutorialRequested = ValueNotifier<bool>(false);
  bool _tutorialSeen = false;

  final Map<QuestMetric, int> _questStats = {
    for (final metric in QuestMetric.values) metric: 0,
  };
  int _questIndex = 0;
  final math.Random _random = math.Random();
  final SaveRepository _saveRepository;

  /// 현재 시각 공급자(테스트에서 고정 시계 주입용).
  final DateTime Function() _now;

  /// 사운드 훅. 기본은 무음 플레이스홀더(에셋 미보유).
  final SoundPlayer _sound;
  final SettingsRepository _settingsRepository;

  /// 사운드 설정(설정 화면 스위치와 연동). 꺼져 있으면 훅을 무시한다.
  final ValueNotifier<bool> soundEnabled = ValueNotifier<bool>(true);

  void _playSound(GameSound sound) {
    if (soundEnabled.value) {
      _sound.play(sound);
    }
  }

  void setSoundEnabled(bool enabled) {
    soundEnabled.value = enabled;
    unawaited(_settingsRepository.saveSoundEnabled(enabled));
  }

  /// 자동 저장 주기(현실 초). 밸런스가 아닌 엔진 설정 값.
  static const double autosaveIntervalRealSeconds = 10;
  double _secondsSinceAutosave = 0;

  Offset _cameraCenter = Offset.zero;
  Rect _worldBounds = Rect.zero;
  double _zoom = 1.0;
  String? _pendingPlacementName;
  double _elapsedGameMinutes = startingGameMinutes.toDouble();
  double _previousElapsedGameMinutes = startingGameMinutes.toDouble();
  int _currentTrafficDay = -1;
  double _reputation = Balance.reputationStart;
  int _lostToday = 0;
  final Set<int> _unlockedPlots = <int>{};
  int _money = Balance.startingMoney;
  int _nextVehicleId = 1;
  int _nextPersonId = 1;

  @override
  Color backgroundColor() => const Color(0xFF698553);

  @override
  Future<void> onLoad() async {
    _buildTileMap();
    _unlockedPlots
      ..clear()
      ..addAll(_startingUnlockedPlots());
    soundEnabled.value = await _settingsRepository.loadSoundEnabled();
    final saved = await _saveRepository.load();
    if (saved != null) {
      _applySaveData(saved);
      _settleOfflineEarnings(saved);
    }
    _tutorialSeen = saved?.tutorialSeen ?? false;
    if (!_tutorialSeen) {
      tutorialRequested.value = true;
    }
    _updateQuestLabel();
    _rebuildTrafficPlan(force: true);
  }

  /// 튜토리얼 완료 처리(다시 표시하지 않도록 저장).
  void completeTutorial() {
    _tutorialSeen = true;
    unawaited(saveNow());
  }

  /// 저장을 지우고 새 게임 상태로 되돌린다. (기기 설정은 유지)
  Future<void> resetGame() async {
    await _saveRepository.clear();

    _money = Balance.startingMoney;
    moneyLabel.value = _formatMoney(_money);
    _elapsedGameMinutes = startingGameMinutes.toDouble();
    _previousElapsedGameMinutes = _elapsedGameMinutes;
    timeLabel.value = _formatGameTime(startingGameMinutes);

    _placedTiles.clear();
    _parkingSlots.removeWhere(
      (slot) => !parkingLabelTileNumbers.contains(slot.spotTileNumber),
    );
    for (final slot in _parkingSlots) {
      slot.occupiedBy = null;
      slot.reservedBy = null;
    }
    _vehicles.clear();
    _people.clear();
    _floatingSaleTexts.clear();
    _dailyArrivals.clear();
    _currentTrafficDay = -1;
    _reputation = Balance.reputationStart;
    reputation.value = _reputation;
    _lostToday = 0;
    congestion.value = 0;
    _unlockedPlots
      ..clear()
      ..addAll(_startingUnlockedPlots());

    _questIndex = 0;
    for (final metric in QuestMetric.values) {
      _questStats[metric] = 0;
    }
    _updateQuestLabel();
    cancelPlacement();

    _tutorialSeen = false;
    tutorialRequested.value = true;
    _rebuildTrafficPlan(force: true);
    notice.value = '데이터를 초기화했습니다';
  }

  /// 평판을 [target](0 또는 100) 쪽으로 [step] 비율만큼 EMA 이동.
  void _nudgeReputation(double target, double step) {
    _reputation =
        (_reputation + (target - _reputation) * step).clamp(0.0, 100.0);
    reputation.value = _reputation;
  }

  /// 차량이 정상 주차(서비스)됐을 때 호출 — 평판 상승.
  void _registerServedVehicle() {
    _nudgeReputation(100, Balance.reputationServedStep);
  }

  /// 차량이 정체로 이탈했을 때 호출 — 평판 하락 + 손실 카운터.
  /// [position]은 이탈 플로팅 표시에 쓰인다(Task 5에서 사용).
  void _registerLostVehicle(Offset position) {
    _nudgeReputation(0, Balance.reputationLostStep);
    _lostToday++;
    congestion.value = _lostToday;
    _floatingSaleTexts.add(
      FloatingSaleText(
        position: position - const Offset(0, 16),
        text: '놓침',
        color: const Color(0xFFE57373),
      ),
    );
  }

  /// 퀘스트 지표를 올리고, 현재 퀘스트가 달성됐으면 보상 지급 후 다음으로.
  void _bumpQuestStat(QuestMetric metric, [int amount = 1]) {
    _questStats[metric] = (_questStats[metric] ?? 0) + amount;
    while (_questIndex < questLine.length) {
      final quest = questLine[_questIndex];
      if ((_questStats[quest.metric] ?? 0) < quest.target) {
        break;
      }
      _money += quest.reward;
      moneyLabel.value = _formatMoney(_money);
      notice.value =
          '퀘스트 완료: ${quest.description} (+${_formatNumber(quest.reward)}원)';
      _playSound(GameSound.questComplete);
      _questIndex++;
    }
    _updateQuestLabel();
  }

  void _updateQuestLabel() {
    if (_questIndex >= questLine.length) {
      questLabel.value = null;
      return;
    }
    final quest = questLine[_questIndex];
    final progress =
        math.min(_questStats[quest.metric] ?? 0, quest.target);
    questLabel.value =
        '목표: ${quest.description} ($progress/${quest.target})';
  }

  /// 부재 시간(현실, 최대 [Balance.offlineEarningsCap])을 게임 시간으로
  /// 환산해 시계를 전진시키고, 매장별 오프라인 매출을 정산한다.
  void _settleOfflineEarnings(GameSaveData saved) {
    final savedAtEpochMs = saved.savedAtEpochMs;
    if (savedAtEpochMs == null) {
      return; // v2 이하 저장
    }
    final awayMs = _now().millisecondsSinceEpoch - savedAtEpochMs;
    if (awayMs <= 0) {
      return; // 시계 역행(기기 시간 변경 등)은 무시
    }

    final cappedSeconds = math.min(
      awayMs / 1000,
      Balance.offlineEarningsCap.inSeconds.toDouble(),
    );
    final offlineGameMinutes = cappedSeconds * gameMinutesPerRealSecond;
    final offlineGameDays = offlineGameMinutes / gameMinutesPerDay;

    _elapsedGameMinutes += offlineGameMinutes;
    _previousElapsedGameMinutes = _elapsedGameMinutes;
    timeLabel.value = _formatGameTime(
      ((_elapsedGameMinutes ~/ 10) * 10).toInt(),
    );

    var amount = 0;
    for (final placed in _placedTiles.values) {
      if (!placed.showLabel) {
        continue;
      }
      final salePrice = Balance.salePriceWith(
        placed.label,
        placed.level,
        placed.staffCount,
      );
      if (salePrice == null) {
        continue;
      }
      amount += (salePrice *
              Balance.offlineSalesPerStorePerDay *
              offlineGameDays)
          .round();
    }
    if (amount <= 0) {
      return;
    }

    _money += amount;
    moneyLabel.value = _formatMoney(_money);
    _playSound(GameSound.offlineEarnings);
    offlineEarnings.value = OfflineEarningsReport(
      amount: amount,
      offlineGameDays: offlineGameDays,
    );
  }

  void _applySaveData(GameSaveData data) {
    _money = data.money;
    moneyLabel.value = _formatMoney(_money);
    _elapsedGameMinutes = data.elapsedGameMinutes;
    _previousElapsedGameMinutes = data.elapsedGameMinutes;
    timeLabel.value = _formatGameTime(
      ((data.elapsedGameMinutes ~/ 10) * 10).toInt(),
    );

    _placedTiles.clear();
    for (final tile in data.placedTiles) {
      // 맵 구조가 바뀌어 존재하지 않는 타일 번호는 조용히 버린다.
      if (!_tileByNumber.containsKey(tile.tileNumber)) {
        continue;
      }
      _placedTiles[tile.tileNumber] = PlacedTileData(
        label: tile.label,
        backgroundColor: const Color(0xFF111111),
        showLabel: tile.showLabel,
        level: tile.level,
        staffCount: tile.staffCount,
      );
    }
    _syncDynamicParkingSlots();

    if (data.unlockedPlots != null) {
      _unlockedPlots
        ..clear()
        ..addAll(data.unlockedPlots!);
    } else {
      // v7 이하(기존 유저): 전체 개방으로 마이그레이션.
      _unlockAllPlots();
    }

    _reputation = data.reputation;
    reputation.value = _reputation;

    _questIndex = data.questIndex.clamp(0, questLine.length);
    for (final metric in QuestMetric.values) {
      _questStats[metric] = data.questStats[metric.name] ?? 0;
    }
  }

  /// 저장에서 복원된 '주차' 타일들을 실제 주차 슬롯으로 재등록한다.
  void _syncDynamicParkingSlots() {
    for (final entry in _placedTiles.entries) {
      if (!_isParkingFacility(entry.value.label)) {
        continue;
      }
      if (_parkingSlotByNumber(entry.key) != null) {
        continue;
      }
      final slot = _createParkingSlotAt(entry.key);
      if (slot != null) {
        _parkingSlots.add(slot);
      }
    }
  }

  /// 신규 주차 슬롯 생성. 분기점에서 차량 진입 경로가 없으면 null.
  ParkingSlot? _createParkingSlotAt(int spotTileNumber) {
    final path = _vehicleTilePathBetween(
      fromTileNumber: parkingJunctionTileNumber,
      toTileNumber: spotTileNumber,
    );
    if (path == null || path.length < 2) {
      return null;
    }
    return ParkingSlot(
      spotTileNumber: spotTileNumber,
      approachTileNumber: path[path.length - 2],
    );
  }

  /// 차량이 달릴 수 있는 주차 존 타일 위 BFS 경로(타일 번호, 출발지 포함).
  /// 대기열 타일·다른 주차 슬롯·진입 도로는 지나지 않는다.
  List<int>? _vehicleTilePathBetween({
    required int fromTileNumber,
    required int toTileNumber,
  }) {
    if (_tileByNumber[fromTileNumber] == null ||
        _tileByNumber[toTileNumber] == null) {
      return null;
    }

    bool drivable(int tileNumber) {
      if (tileNumber == toTileNumber) {
        return true;
      }
      final tile = _tileByNumber[tileNumber]!;
      if (tile.zone != TileZone.parking ||
          tile.logicalY >= entryRoadStartY) {
        return false;
      }
      if (leftQueueTileNumbers.contains(tileNumber) ||
          rightQueueTileNumbers.contains(tileNumber)) {
        return false;
      }
      return !_parkingSlots.any((slot) => slot.spotTileNumber == tileNumber);
    }

    final queue = <int>[fromTileNumber];
    final previous = <int, int?>{fromTileNumber: null};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == toTileNumber) {
        break;
      }
      for (final neighbor in _neighborTileNumbers(_tileByNumber[current]!)) {
        if (previous.containsKey(neighbor) || !drivable(neighbor)) {
          continue;
        }
        previous[neighbor] = current;
        queue.add(neighbor);
      }
    }

    if (!previous.containsKey(toTileNumber)) {
      return null;
    }
    final path = <int>[];
    int? cursor = toTileNumber;
    while (cursor != null) {
      path.add(cursor);
      cursor = previous[cursor];
    }
    return path.reversed.toList();
  }

  GameSaveData _currentSaveData() {
    return GameSaveData(
      money: _money,
      elapsedGameMinutes: _elapsedGameMinutes,
      savedAtEpochMs: _now().millisecondsSinceEpoch,
      questIndex: _questIndex,
      questStats: {
        for (final entry in _questStats.entries) entry.key.name: entry.value,
      },
      tutorialSeen: _tutorialSeen,
      reputation: _reputation,
      unlockedPlots: _unlockedPlots.toList(),
      placedTiles: [
        for (final entry in _placedTiles.entries)
          PlacedTileSave(
            tileNumber: entry.key,
            label: entry.value.label,
            showLabel: entry.value.showLabel,
            level: entry.value.level,
            staffCount: entry.value.staffCount,
          ),
      ],
    );
  }

  /// 현재 진행 상태를 즉시 저장한다. (건설 직후, 앱 백그라운드 전환,
  /// 자동 저장 주기마다 호출)
  Future<void> saveNow() => _saveRepository.save(_currentSaveData());

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (size.x <= 0 || size.y <= 0) {
      return;
    }

    _cameraCenter = _clampCameraCenter(_cameraCenter);
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final viewport = Rect.fromLTWH(0, 0, size.x, size.y);
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF8EB06E),
          Color(0xFF5C7747),
        ],
      ).createShader(viewport);
    canvas.drawRect(viewport, background);

    canvas.save();
    canvas.translate(size.x * 0.5, size.y * 0.5);
    canvas.scale(_zoom);
    canvas.translate(-_cameraCenter.dx, -_cameraCenter.dy);
    _drawTileMap(canvas);
    _drawPeople(canvas);
    _drawFloatingSaleTexts(canvas);
    canvas.restore();
  }

  void _drawFloatingSaleTexts(Canvas canvas) {
    for (final floating in _floatingSaleTexts) {
      final opacity =
          (1 - (floating.age / floatingSaleLifetimeSeconds)).clamp(0.0, 1.0);
      final painter = TextPainter(
        text: TextSpan(
          text: floating.text,
          style: TextStyle(
            color: floating.color.withValues(alpha: opacity),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(
                color: const Color(0xFF1E1A16).withValues(alpha: opacity),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      painter.paint(
        canvas,
        floating.position -
            Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _previousElapsedGameMinutes = _elapsedGameMinutes;
    _elapsedGameMinutes += dt * gameMinutesPerRealSecond;
    final snappedMinutes = ((_elapsedGameMinutes ~/ 10) * 10);
    final nextLabel = _formatGameTime(snappedMinutes);
    if (timeLabel.value != nextLabel) {
      timeLabel.value = nextLabel;
    }

    _rebuildTrafficPlan();
    _spawnScheduledVehicles(
      windowStartMinute: _previousElapsedGameMinutes,
      windowEndMinute: _elapsedGameMinutes,
    );
    _updateVehicles(dt);
    _updatePeople(dt);
    _promoteQueuedVehicles();

    for (final floating in _floatingSaleTexts) {
      floating.age += dt;
      floating.position -= Offset(0, floatingSaleRiseSpeed * dt);
    }
    _floatingSaleTexts
        .removeWhere((floating) => floating.age >= floatingSaleLifetimeSeconds);

    _secondsSinceAutosave += dt;
    if (_secondsSinceAutosave >= autosaveIntervalRealSeconds) {
      _secondsSinceAutosave = 0;
      unawaited(saveNow());
    }
  }

  void panBy(Offset delta) {
    if (_tiles.isEmpty) {
      return;
    }

    _cameraCenter = _clampCameraCenter(
      _cameraCenter - Offset(delta.dx / _zoom, delta.dy / _zoom),
    );
  }

  void zoomAt({
    required double scaleDelta,
    required Offset focalPoint,
  }) {
    if (_tiles.isEmpty || scaleDelta == 1) {
      return;
    }

    final previousZoom = _zoom;
    final nextZoom = (_zoom * scaleDelta).clamp(minZoom, maxZoom);
    if ((nextZoom - previousZoom).abs() < 0.0001) {
      return;
    }

    final focalWorldBefore = _screenToWorld(focalPoint, previousZoom);
    _zoom = nextZoom;
    final focalWorldAfter = _screenToWorld(focalPoint, _zoom);
    _cameraCenter = _clampCameraCenter(
      _cameraCenter + (focalWorldBefore - focalWorldAfter),
    );
  }

  void startPlacement(String itemName) {
    _pendingPlacementName = itemName;
    pendingPlacementLabel.value = itemName;
  }

  void cancelPlacement() {
    _pendingPlacementName = null;
    pendingPlacementLabel.value = null;
  }

  List<String> get todayArrivalSchedule {
    if (_dailyArrivals.isEmpty) {
      return const <String>[];
    }

    final today = (_elapsedGameMinutes ~/ gameMinutesPerDay).toInt();
    return _dailyArrivals
        .where(
          (arrival) =>
              (arrival.spawnMinute ~/ gameMinutesPerDay).toInt() == today,
        )
        .map(
          (arrival) =>
              '${_formatClockOnly(arrival.spawnMinute)} ${arrival.type.label}',
        )
        .toList(growable: false);
  }

  void handleTap(Offset screenPoint) {
    if (_pendingPlacementName == null) {
      _handleStoreTap(screenPoint);
      return;
    }

    final targetTile = _currentPlacementTile;
    if (targetTile == null) {
      return;
    }

    final footprint =
        _placementFootprintFor(targetTile, _pendingPlacementName!);
    if (footprint == null) {
      return;
    }

    final worldPoint = _screenToWorld(screenPoint, _zoom);
    final tappedPlacementTile = footprint
        .map((tileNumber) => _tileByNumber[tileNumber]!)
        .any((tile) => tile.path.contains(worldPoint));
    if (!tappedPlacementTile) {
      return;
    }

    if (_tryBuild(_pendingPlacementName!, footprint)) {
      _pendingPlacementName = null;
      pendingPlacementLabel.value = null;
    }
  }

  /// 배치 모드가 아닐 때의 맵 탭: 배치된 매장이면 업그레이드 요청을 발행한다.
  void _handleStoreTap(Offset screenPoint) {
    final worldPoint = _screenToWorld(screenPoint, _zoom);

    // 잠긴 부지 탭이면 해금 흐름으로 라우팅한다(잠긴 타일엔 매장이 없다).
    for (final tile in _tiles) {
      if (!tile.path.contains(worldPoint)) {
        continue;
      }
      if (tile.logicalY < entryRoadStartY && !_isPlotUnlocked(tile)) {
        final key = _plotKeyForTile(tile);
        if (_isPlotAdjacentToUnlocked(key)) {
          landUnlockRequest.value =
              LandUnlockRequest(plotKey: key, cost: _currentLandUnlockCost());
        } else {
          notice.value = '인접한 구역만 해금할 수 있습니다';
        }
        return;
      }
      break;
    }

    for (final entry in _placedTiles.entries) {
      final tile = _tileByNumber[entry.key];
      if (tile == null || !tile.path.contains(worldPoint)) {
        continue;
      }
      final anchorTileNumber = _storeAnchorFor(entry.key, entry.value);
      if (anchorTileNumber == null) {
        return; // 주차 등 업그레이드 불가 시설
      }
      final placed = _placedTiles[anchorTileNumber]!;
      upgradeRequest.value = StoreUpgradeRequest(
        anchorTileNumber: anchorTileNumber,
        storeName: placed.label,
        level: placed.level,
        currentSalePrice: Balance.salePriceWith(
              placed.label,
              placed.level,
              placed.staffCount,
            ) ??
            0,
        nextSalePrice: placed.level >= Balance.storeMaxLevel
            ? null
            : Balance.salePriceWith(
                placed.label,
                placed.level + 1,
                placed.staffCount,
              ),
        upgradeCost: Balance.upgradeCostOf(placed.label, placed.level),
        staffCount: placed.staffCount,
        staffHireCost: Balance.staffHireCostOf(placed.label, placed.staffCount),
      );
      return;
    }
  }

  /// 배치 타일에서 매장 앵커(showLabel 타일) 번호를 찾는다. 매장이 아니면 null.
  int? _storeAnchorFor(int tileNumber, PlacedTileData data) {
    if (!Balance.storeSpecs.containsKey(data.label)) {
      return null;
    }
    if (data.showLabel) {
      return tileNumber;
    }
    final tile = _tileByNumber[tileNumber]!;
    final above = _tileAt(
      logicalX: tile.logicalX,
      logicalY: tile.logicalY - 1,
    );
    if (above == null) {
      return null;
    }
    final abovePlaced = _placedTiles[above.tileNumber];
    if (abovePlaced != null &&
        abovePlaced.label == data.label &&
        abovePlaced.showLabel) {
      return above.tileNumber;
    }
    return null;
  }

  /// 매장 업그레이드 시도. 결과(성공/최대 레벨/잔액 부족)는 notice로 알린다.
  void upgradeStore(int anchorTileNumber) {
    final placed = _placedTiles[anchorTileNumber];
    if (placed == null || !placed.showLabel) {
      return;
    }
    final upgradeCost = Balance.upgradeCostOf(placed.label, placed.level);
    if (upgradeCost == null) {
      notice.value = '${placed.label}: 이미 최대 레벨입니다';
      return;
    }
    if (_money < upgradeCost) {
      notice.value =
          '잔액이 부족합니다 — 업그레이드에 ${_formatNumber(upgradeCost)}원 필요';
      _playSound(GameSound.error);
      return;
    }

    _money -= upgradeCost;
    moneyLabel.value = _formatMoney(_money);
    _placedTiles[anchorTileNumber] = PlacedTileData(
      label: placed.label,
      backgroundColor: placed.backgroundColor,
      showLabel: true,
      level: placed.level + 1,
      staffCount: placed.staffCount,
    );
    notice.value = '${placed.label} Lv.${placed.level + 1} 업그레이드 완료';
    _playSound(GameSound.upgrade);
    _bumpQuestStat(QuestMetric.upgradesDone);
    unawaited(saveNow());
  }

  /// 매장 직원 고용 시도. 결과(성공/최대 인원/잔액 부족)는 notice로 알린다.
  void hireStaff(int anchorTileNumber) {
    final placed = _placedTiles[anchorTileNumber];
    if (placed == null || !placed.showLabel) {
      return;
    }
    final hireCost = Balance.staffHireCostOf(placed.label, placed.staffCount);
    if (hireCost == null) {
      notice.value = '${placed.label}: 직원이 이미 최대 인원입니다';
      return;
    }
    if (_money < hireCost) {
      notice.value =
          '잔액이 부족합니다 — 직원 고용에 ${_formatNumber(hireCost)}원 필요';
      _playSound(GameSound.error);
      return;
    }

    _money -= hireCost;
    moneyLabel.value = _formatMoney(_money);
    _placedTiles[anchorTileNumber] = PlacedTileData(
      label: placed.label,
      backgroundColor: placed.backgroundColor,
      showLabel: true,
      level: placed.level,
      staffCount: placed.staffCount + 1,
    );
    notice.value =
        '${placed.label} 직원 고용 완료 (${placed.staffCount + 1}/${Balance.maxStaffPerStore}명)';
    _playSound(GameSound.hireStaff);
    _bumpQuestStat(QuestMetric.staffHired);
    unawaited(saveNow());
  }

  bool _tryBuild(String itemName, List<int> footprint) {
    final buildCost = Balance.buildCostOf(itemName);
    if (buildCost != null && _money < buildCost) {
      notice.value = '잔액이 부족합니다 — $itemName 건설에 ${_formatNumber(buildCost)}원 필요';
      _playSound(GameSound.error);
      return false;
    }

    ParkingSlot? newSlot;
    if (_isParkingFacility(itemName)) {
      newSlot = _createParkingSlotAt(footprint.first);
      if (newSlot == null) {
        notice.value = '차량이 진입할 수 없는 위치입니다';
        _playSound(GameSound.error);
        return false;
      }
    }

    for (var i = 0; i < footprint.length; i++) {
      final tileNumber = footprint[i];
      _placedTiles[tileNumber] = PlacedTileData(
        label: itemName,
        backgroundColor: const Color(0xFF111111),
        showLabel: i == 0,
      );
    }
    if (buildCost != null) {
      _money -= buildCost;
      moneyLabel.value = _formatMoney(_money);
    }
    if (newSlot != null) {
      _parkingSlots.add(newSlot);
    }
    _playSound(GameSound.build);
    if (_isParkingFacility(itemName)) {
      _bumpQuestStat(QuestMetric.parkingBuilt);
    } else if (_isStore(itemName)) {
      _bumpQuestStat(QuestMetric.storesBuilt);
    }
    unawaited(saveNow());
    return true;
  }

  @visibleForTesting
  Map<int, PlacedTileData> get debugPlacedTiles => _placedTiles;

  @visibleForTesting
  int get debugMoney => _money;

  @visibleForTesting
  set debugMoney(int value) {
    _money = value;
    moneyLabel.value = _formatMoney(value);
  }

  /// 현재 카메라 기준 배치 타일에 [itemName]을 건설한다. 테스트 전용.
  @visibleForTesting
  bool debugBuild(String itemName) {
    final anchorTile = _placementTileFor(itemName);
    if (anchorTile == null) {
      return false;
    }
    final footprint = _placementFootprintFor(anchorTile, itemName);
    if (footprint == null) {
      return false;
    }
    return _tryBuild(itemName, footprint);
  }

  @visibleForTesting
  void debugRecordSaleAt(int anchorTileNumber) =>
      _recordSaleAt(anchorTileNumber);

  /// 지정 타일 중심을 탭한 것처럼 handleTap을 호출한다. 테스트 전용.
  @visibleForTesting
  void debugTapTile(int tileNumber) {
    final center = _tileCenterByNumber(tileNumber);
    handleTap(
      Offset(
        ((center.dx - _cameraCenter.dx) * _zoom) + (size.x * 0.5),
        ((center.dy - _cameraCenter.dy) * _zoom) + (size.y * 0.5),
      ),
    );
  }

  @visibleForTesting
  StoreVisitPlan? debugPlanStoreVisit(int startTileNumber) =>
      _planStoreVisit(startTileNumber);

  @visibleForTesting
  List<ParkingSlot> get debugParkingSlots => _parkingSlots;

  @visibleForTesting
  List<StoreVisitPlan> debugReachableStorePlans(int startTileNumber) =>
      _reachableStorePlans(startTileNumber);

  @visibleForTesting
  double debugStoreWeightFor(String storeName, VehicleType type) =>
      _storeWeightFor(storeName, type);

  @visibleForTesting
  StoreVisitPlan debugPickWeightedStorePlan(
    List<StoreVisitPlan> plans,
    VehicleType type,
  ) =>
      _pickWeightedStorePlan(plans, type);

  @visibleForTesting
  List<WalkingPerson> get debugPeople => _people;

  @visibleForTesting
  double get debugElapsedGameMinutes => _elapsedGameMinutes;

  @visibleForTesting
  int get debugQuestIndex => _questIndex;

  @visibleForTesting
  Map<QuestMetric, int> get debugQuestStats => _questStats;

  @visibleForTesting
  int get debugFloatingSaleTextCount => _floatingSaleTexts.length;

  @visibleForTesting
  double get debugReputation => _reputation;

  @visibleForTesting
  set debugReputation(double value) {
    _reputation = value;
    reputation.value = value;
  }

  @visibleForTesting
  int get debugLostToday => _lostToday;

  @visibleForTesting
  void debugRegisterServedVehicle() => _registerServedVehicle();

  @visibleForTesting
  void debugRegisterLostVehicle() => _registerLostVehicle(Offset.zero);

  @visibleForTesting
  VehicleDemandRange debugDailyDemandRange(VehicleType type) =>
      _dailyDemandRange(type);

  @visibleForTesting
  int get debugVehicleCount => _vehicles.length;

  @visibleForTesting
  Map<String, int> get debugVehicleStateCounts {
    final counts = <String, int>{};
    for (final vehicle in _vehicles) {
      counts[vehicle.state.name] = (counts[vehicle.state.name] ?? 0) + 1;
    }
    return counts;
  }

  @visibleForTesting
  int get debugPendingArrivalCount => _dailyArrivals.length;

  @visibleForTesting
  int get debugUnlockedPlotCount => _unlockedPlots.length;

  @visibleForTesting
  void debugUnlockAllPlots() => _unlockAllPlots();

  @visibleForTesting
  int? debugFirstAdjacentLockedPlot() {
    final total = _plotsPerRow * (mapRows ~/ Balance.landPlotSize);
    for (var key = 0; key < total; key++) {
      if (!_unlockedPlots.contains(key) && _isPlotAdjacentToUnlocked(key)) {
        return key;
      }
    }
    return null;
  }

  /// 지정한 타일에 [itemName]을 건설한다. 테스트 전용.
  @visibleForTesting
  bool debugBuildAt(int tileNumber, String itemName) {
    final anchorTile = _tileByNumber[tileNumber];
    if (anchorTile == null) {
      return false;
    }
    final footprint = _placementFootprintFor(anchorTile, itemName);
    if (footprint == null) {
      return false;
    }
    return _tryBuild(itemName, footprint);
  }

  @visibleForTesting
  List<Offset> debugArrivalRouteFor(ParkingSlot slot) =>
      _routeForParkingSlot(slot);

  @visibleForTesting
  List<Offset> debugExitRouteFor(ParkingSlot slot) => _exitRouteFor(slot);

  /// 현재 배치 하이라이트 타일의 화면 좌표(탭 시뮬레이션용). 테스트 전용.
  @visibleForTesting
  Offset? debugPlacementScreenPoint() {
    final tile = _currentPlacementTile;
    if (tile == null) {
      return null;
    }
    return Offset(
      ((tile.center.dx - _cameraCenter.dx) * _zoom) + (size.x * 0.5),
      ((tile.center.dy - _cameraCenter.dy) * _zoom) + (size.y * 0.5),
    );
  }

  @visibleForTesting
  Offset debugTileCenter(int tileNumber) => _tileCenterByNumber(tileNumber);

  void _buildTileMap() {
    _tiles
      ..clear()
      ..addAll(_buildMainField())
      ..addAll(_buildEntryRoad());

    _tiles.sort((a, b) {
      final depthCompare = (a.logicalX + a.logicalY).compareTo(
        b.logicalX + b.logicalY,
      );
      if (depthCompare != 0) {
        return depthCompare;
      }
      return a.logicalY.compareTo(b.logicalY);
    });

    for (var i = 0; i < _tiles.length; i++) {
      _tiles[i].tileNumber = i + 1;
      _tiles[i].updateNumberPainters();
    }

    _tileByNumber
      ..clear()
      ..addEntries(_tiles.map((tile) => MapEntry(tile.tileNumber, tile)));

    _tileByCoordinate
      ..clear()
      ..addEntries(
        _tiles.map((tile) => MapEntry((tile.logicalX, tile.logicalY), tile)),
      );

    _treeTileNumbers
      ..clear()
      ..addAll(treeTileNumbers)
      ..addAll(
        _tiles
            .where(
              (tile) =>
                  tile.zone == TileZone.commercial && tile.tileNumber < 1930,
            )
            .map((tile) => tile.tileNumber),
      )
      ..addAll(
        _tiles
            .where(
              (tile) =>
                  ((tile.logicalX == 31 || tile.logicalX == 32) &&
                      tile.logicalY >= 41) ||
                  ((tile.logicalX == 28 ||
                          tile.logicalX == 29 ||
                          tile.logicalX == 30) &&
                      tile.logicalY >= 40),
            )
            .map((tile) => tile.tileNumber),
      );

    _treeTileNumbers.removeAll({
      for (var tileNumber = 1995; tileNumber <= 2226; tileNumber++) tileNumber,
      for (var tileNumber = 2026; tileNumber <= 2251; tileNumber++) tileNumber,
      for (var tileNumber = 2056; tileNumber <= 2275; tileNumber++) tileNumber,
    });
    _treeTileNumbers.addAll(
      _tiles
          .where((tile) => tile.logicalX == 30 && tile.logicalY >= 41)
          .map((tile) => tile.tileNumber),
    );

    _worldBounds = _computeWorldBounds();
    _cameraCenter = _tileByNumber[2147]?.center ?? _worldBounds.center;
  }

  List<MapTile> _buildMainField() {
    return List<MapTile>.generate(mapColumns * mapRows, (index) {
      final logicalY = (index ~/ mapColumns) + 1;
      final logicalX = (index % mapColumns) + 1;
      return MapTile(
        logicalX: logicalX,
        logicalY: logicalY,
        zone: logicalX <= parkingEndX ? TileZone.parking : TileZone.commercial,
        center: _tileCenter(logicalX: logicalX, logicalY: logicalY),
      );
    });
  }

  List<MapTile> _buildEntryRoad() {
    final tiles = <MapTile>[];
    for (var logicalX = entryRoadLeftX;
        logicalX <= entryRoadRightX;
        logicalX++) {
      for (var logicalY = entryRoadStartY;
          logicalY <= entryRoadEndY;
          logicalY++) {
        tiles.add(
          MapTile(
            logicalX: logicalX,
            logicalY: logicalY,
            zone: TileZone.parking,
            center: _tileCenter(logicalX: logicalX, logicalY: logicalY),
          ),
        );
      }
    }
    return tiles;
  }

  Offset _tileCenter({
    required int logicalX,
    required int logicalY,
  }) {
    final column = logicalX - 1;
    final row = logicalY - 1;
    return Offset(
      (column + row) * tileHalfWidth,
      (row - column) * tileHalfHeight,
    );
  }

  Rect _computeWorldBounds() {
    if (_tiles.isEmpty) {
      return Rect.zero;
    }

    var left = double.infinity;
    var top = double.infinity;
    var right = double.negativeInfinity;
    var bottom = double.negativeInfinity;

    for (final tile in _tiles) {
      left = math.min(left, tile.bounds.left);
      top = math.min(top, tile.bounds.top);
      right = math.max(right, tile.bounds.right);
      bottom = math.max(bottom, tile.bounds.bottom);
    }

    return Rect.fromLTRB(left, top, right, bottom);
  }

  Offset _screenToWorld(Offset screenPoint, double zoom) {
    return Offset(
      ((screenPoint.dx - (size.x * 0.5)) / zoom) + _cameraCenter.dx,
      ((screenPoint.dy - (size.y * 0.5)) / zoom) + _cameraCenter.dy,
    );
  }

  Offset _clampCameraCenter(Offset desired) {
    if (_worldBounds == Rect.zero || size.x <= 0 || size.y <= 0) {
      return desired;
    }

    final halfViewportWidth = (size.x * 0.5) / _zoom;
    final halfViewportHeight = (size.y * 0.5) / _zoom;

    final minX = _worldBounds.left + halfViewportWidth - cameraMargin;
    final maxX = _worldBounds.right - halfViewportWidth + cameraMargin;
    final minY = _worldBounds.top + halfViewportHeight - cameraMargin;
    final maxY = _worldBounds.bottom - halfViewportHeight + cameraMargin;

    final x =
        minX > maxX ? _worldBounds.center.dx : desired.dx.clamp(minX, maxX);
    final y =
        minY > maxY ? _worldBounds.center.dy : desired.dy.clamp(minY, maxY);
    return Offset(x.toDouble(), y.toDouble());
  }

  void _drawTileMap(Canvas canvas) {
    final worldViewport = Rect.fromCenter(
      center: _cameraCenter,
      width: size.x / _zoom,
      height: size.y / _zoom,
    );

    final drawViewport = worldViewport.inflate(tileHalfWidth * 3);
    final borderPaint = Paint()
      // ignore: deprecated_member_use
      ..color = const Color(0xFF2E2618).withOpacity(0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final placementTile = _currentPlacementTile;
    final placementFootprint =
        placementTile == null || _pendingPlacementName == null
            ? const <int>{}
            : _placementFootprintFor(placementTile, _pendingPlacementName!)!
                .toSet();

    for (final tile in _tiles) {
      if (!tile.bounds.overlaps(drawViewport)) {
        continue;
      }

      canvas.drawPath(tile.path, Paint()..color = _tileColor(tile));
      canvas.drawPath(tile.path, borderPaint);
      if (placementFootprint.contains(tile.tileNumber)) {
        canvas.drawPath(
          tile.path,
          Paint()..color = const Color(0xFF808080),
        );
        canvas.drawPath(tile.path, borderPaint);
      }

      final placedData = _placedTiles[tile.tileNumber];
      final specialLabel = _specialLabelFor(tile);
      if (placedData != null && placedData.showLabel) {
        _drawSpecialLabel(
          canvas,
          tile,
          placedData.level > 1
              ? '${placedData.label} Lv.${placedData.level}'
              : placedData.label,
          '${tile.tileNumber}',
        );
      } else if (specialLabel != null) {
        _drawSpecialLabel(
          canvas,
          tile,
          specialLabel,
          '${tile.tileNumber}',
        );
      } else {
        _drawTileLabel(canvas, tile);
      }
    }

    _drawVehicles(canvas);
  }

  void _drawVehicles(Canvas canvas) {
    for (final vehicle in _vehicles) {
      final size = vehicle.state == VehicleState.parked ? 16.0 : 18.0;
      final rect = Rect.fromCenter(
        center: vehicle.position,
        width: size,
        height: size,
      );
      canvas.drawRect(rect, Paint()..color = vehicle.type.color);
      canvas.drawRect(
        rect,
        Paint()
          ..color = const Color(0xFF171717)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _drawPeople(Canvas canvas) {
    for (final person in _people) {
      final fillPaint = Paint()..color = person.type.color;
      final outlinePaint = Paint()
        ..color = const Color(0xFF171717)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final center = person.position;

      switch (person.type.shape) {
        case PersonShape.circle:
          canvas.drawCircle(center, 5, fillPaint);
          canvas.drawCircle(center, 5, outlinePaint);
        case PersonShape.triangle:
          final path = Path()
            ..moveTo(center.dx, center.dy - 6)
            ..lineTo(center.dx + 5, center.dy + 4)
            ..lineTo(center.dx - 5, center.dy + 4)
            ..close();
          canvas.drawPath(path, fillPaint);
          canvas.drawPath(path, outlinePaint);
        case PersonShape.square:
          final rect = Rect.fromCenter(center: center, width: 10, height: 10);
          canvas.drawRect(rect, fillPaint);
          canvas.drawRect(rect, outlinePaint);
        case PersonShape.star:
          final path = _buildStarPath(center, 6, 3);
          canvas.drawPath(path, fillPaint);
          canvas.drawPath(path, outlinePaint);
      }
    }
  }

  Path _buildStarPath(Offset center, double outerRadius, double innerRadius) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = (-math.pi / 2) + (i * math.pi / 5);
      final radius = i.isEven ? outerRadius : innerRadius;
      final point = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    return path;
  }

  void _drawTileLabel(Canvas canvas, MapTile tile) {
    // 타일 번호는 개발 참조용 — 릴리즈 빌드에서는 숨긴다.
    if (!kDebugMode || _zoom < 0.9) {
      return;
    }

    final painter =
        _zoom >= 1.4 ? tile.largeNumberPainter : tile.smallNumberPainter;

    painter.paint(
      canvas,
      Offset(
        tile.center.dx - (painter.width / 2),
        tile.center.dy - (painter.height / 2),
      ),
    );
  }

  void _drawSpecialLabel(
    Canvas canvas,
    MapTile tile,
    String label,
    String tileNumber,
  ) {
    final painters = _specialLabelPainterCache.putIfAbsent(
      '$label|$tileNumber',
      () => _SpecialLabelPainters(
        label: _buildTextPainter(
          text: label,
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          maxWidth: tileHalfWidth * 1.45,
        ),
        number: _buildTextPainter(
          text: tileNumber,
          color: Colors.white,
          fontSize: 6.5,
          fontWeight: FontWeight.w600,
          maxWidth: tileHalfWidth * 1.45,
        ),
      ),
    );
    final labelPainter = painters.label;
    final numberPainter = painters.number;

    // 릴리즈 빌드에서는 시설 이름만 표시(타일 번호 생략).
    if (!kDebugMode) {
      labelPainter.paint(
        canvas,
        Offset(
          tile.center.dx - (labelPainter.width / 2),
          tile.center.dy - (labelPainter.height / 2),
        ),
      );
      return;
    }

    final totalHeight = labelPainter.height + 2 + numberPainter.height;
    final startY = tile.center.dy - (totalHeight / 2);

    labelPainter.paint(
      canvas,
      Offset(
        tile.center.dx - (labelPainter.width / 2),
        startY,
      ),
    );
    numberPainter.paint(
      canvas,
      Offset(
        tile.center.dx - (numberPainter.width / 2),
        startY + labelPainter.height + 2,
      ),
    );
  }

  TextPainter _buildTextPainter({
    required String text,
    required Color color,
    required double fontSize,
    required FontWeight fontWeight,
    required double maxWidth,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout(maxWidth: maxWidth);
  }

  Color _tileColor(MapTile tile) {
    final placedData = _placedTiles[tile.tileNumber];
    if (placedData != null) {
      return placedData.backgroundColor;
    }
    if (_treeTileNumbers.contains(tile.tileNumber)) {
      return const Color(0xFF2F7A3C);
    }
    if (_specialLabelFor(tile) != null) {
      return const Color(0xFF111111);
    }
    if (tile.zone == TileZone.parking) {
      return const Color(0xFFA7A7A7);
    }
    return const Color(0xFFCC9C65);
  }

  String? _specialLabelFor(MapTile tile) {
    if (_treeTileNumbers.contains(tile.tileNumber)) {
      return '나무';
    }
    if (restroomTileNumbers.contains(tile.tileNumber)) {
      return '화장실';
    }
    if (parkingLabelTileNumbers.contains(tile.tileNumber)) {
      return '주차';
    }
    return null;
  }

  MapTile? get _currentPlacementTile {
    if (_pendingPlacementName == null) {
      return null;
    }
    return _placementTileFor(_pendingPlacementName!);
  }

  MapTile? _placementTileFor(String itemName) {
    final targetZone = _placementZoneFor(itemName);
    MapTile? best;
    var bestDistance = double.infinity;
    for (final tile in _tiles) {
      if (tile.zone != targetZone) {
        continue;
      }
      if (_placementFootprintFor(tile, itemName) == null) {
        continue;
      }

      final distance = (tile.center - _cameraCenter).distanceSquared;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = tile;
      }
    }
    return best;
  }

  static const int _plotsPerRow = mapColumns ~/ Balance.landPlotSize;

  int _plotKeyForTile(MapTile tile) =>
      ((tile.logicalX - 1) ~/ Balance.landPlotSize) * _plotsPerRow +
      ((tile.logicalY - 1) ~/ Balance.landPlotSize);

  int? _plotKeyForTileNumber(int tileNumber) {
    final tile = _tileByNumber[tileNumber];
    return tile == null ? null : _plotKeyForTile(tile);
  }

  bool _isPlotUnlocked(MapTile tile) =>
      _unlockedPlots.contains(_plotKeyForTile(tile));

  bool _isPlotAdjacentToUnlocked(int plotKey) {
    final px = plotKey ~/ _plotsPerRow;
    final py = plotKey % _plotsPerRow;
    final rows = mapRows ~/ Balance.landPlotSize;
    const deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    for (final d in deltas) {
      final nx = px + d.$1;
      final ny = py + d.$2;
      if (nx < 0 || nx >= _plotsPerRow || ny < 0 || ny >= rows) {
        continue;
      }
      if (_unlockedPlots.contains(nx * _plotsPerRow + ny)) {
        return true;
      }
    }
    return false;
  }

  int _currentLandUnlockCost() => Balance.landUnlockCost(
        _unlockedPlots.length - _startingUnlockedPlots().length,
      );

  /// 모든 플롯을 연다(구버전 저장 마이그레이션·테스트용).
  void _unlockAllPlots() {
    final total = _plotsPerRow * (mapRows ~/ Balance.landPlotSize);
    for (var i = 0; i < total; i++) {
      _unlockedPlots.add(i);
    }
  }

  /// 플롯을 해금한다. 인접·잔액 조건을 만족하면 true.
  bool unlockPlot(int plotKey) {
    if (_unlockedPlots.contains(plotKey) ||
        !_isPlotAdjacentToUnlocked(plotKey)) {
      return false;
    }
    final cost = _currentLandUnlockCost();
    if (_money < cost) {
      notice.value = '잔액이 부족합니다 — 부지 해금에 ${_formatNumber(cost)}원 필요';
      _playSound(GameSound.error);
      return false;
    }
    _money -= cost;
    moneyLabel.value = _formatMoney(_money);
    _unlockedPlots.add(plotKey);
    notice.value = '부지를 해금했습니다 (-${_formatNumber(cost)}원)';
    _playSound(GameSound.build);
    unawaited(saveNow());
    return true;
  }

  /// 기능적 시작 영역(초기 상업 2147 + 기본 주차 2092·2121)을 덮는 플롯.
  Set<int> _startingUnlockedPlots() {
    final keys = <int>{};
    for (final tileNumber in const [2147, 2092, 2121]) {
      final key = _plotKeyForTileNumber(tileNumber);
      if (key != null) {
        keys.add(key);
      }
    }
    return keys;
  }

  List<int>? _placementFootprintFor(MapTile anchorTile, String itemName) {
    if (_specialLabelFor(anchorTile) != null ||
        _placedTiles.containsKey(anchorTile.tileNumber) ||
        !_isPlotUnlocked(anchorTile)) {
      return null;
    }

    if (_isParkingFacility(itemName)) {
      // 진입 도로(y ≥ entryRoadStartY)와 차량 도로 타일에는 배치 불가.
      if (anchorTile.zone != TileZone.parking ||
          anchorTile.logicalY >= entryRoadStartY ||
          vehicleCorridorTileNumbers.contains(anchorTile.tileNumber)) {
        return null;
      }
      return [anchorTile.tileNumber];
    }

    if (!_isStore(itemName)) {
      return [anchorTile.tileNumber];
    }

    final footprint = <int>[];
    for (var dy = 0; dy <= 1; dy++) {
      final tile = _tileAt(
        logicalX: anchorTile.logicalX,
        logicalY: anchorTile.logicalY + dy,
      );
      if (tile == null ||
          tile.zone != TileZone.commercial ||
          !_isPlotUnlocked(tile) ||
          _specialLabelFor(tile) != null ||
          _placedTiles.containsKey(tile.tileNumber)) {
        return null;
      }
      footprint.add(tile.tileNumber);
    }
    return footprint;
  }

  bool _isStore(String itemName) => Balance.storeSpecs.containsKey(itemName);

  bool _isParkingFacility(String itemName) => itemName == '주차';

  TileZone _placementZoneFor(String itemName) {
    if (_isParkingFacility(itemName)) {
      return TileZone.parking;
    }
    return TileZone.commercial;
  }

  MapTile? _tileAt({
    required int logicalX,
    required int logicalY,
  }) {
    return _tileByCoordinate[(logicalX, logicalY)];
  }

  void _rebuildTrafficPlan({bool force = false}) {
    final day = (_elapsedGameMinutes ~/ gameMinutesPerDay).toInt();
    if (!force && day == _currentTrafficDay) {
      return;
    }

    _currentTrafficDay = day;
    _lostToday = 0;
    congestion.value = 0;
    _dailyArrivals
      ..clear()
      ..addAll(_buildDailyArrivals(day));
  }

  List<DailyArrival> _buildDailyArrivals(int day) {
    final dayStartMinute = day * gameMinutesPerDay;
    final arrivals = <DailyArrival>[];
    for (final type in VehicleType.values) {
      final range = _dailyDemandRange(type);
      final actualCount = _randomizedCount(range);
      for (var i = 0; i < actualCount; i++) {
        final segmentLength = actualCount <= 0
            ? gameMinutesPerDay
            : gameMinutesPerDay / actualCount;
        final segmentStart = dayStartMinute + (segmentLength * i);
        final spawnMinute =
            segmentStart + (_random.nextDouble() * segmentLength);
        if (spawnMinute <= _elapsedGameMinutes) {
          continue;
        }
        arrivals.add(
          DailyArrival(
            type: type,
            spawnMinute: spawnMinute,
          ),
        );
      }
    }

    arrivals.sort((a, b) => a.spawnMinute.compareTo(b.spawnMinute));
    return arrivals;
  }

  VehicleDemandRange _dailyDemandRange(VehicleType type) {
    final modifier = _buildingModifierFor(type);
    final base = switch (type) {
      VehicleType.sedan => Balance.sedanDailyBase,
      VehicleType.truck => Balance.truckDailyBase,
      VehicleType.bus => Balance.busDailyBase,
    };
    final factor = Balance.demandFactor(_reputation);
    return VehicleDemandRange(
      min: (base.min + modifier.min) * factor,
      max: (base.max + modifier.max) * factor,
    );
  }

  VehicleDemandRange _buildingModifierFor(VehicleType type) {
    var minModifier = 0.0;
    var maxModifier = 0.0;
    for (final placed in _placedTiles.values) {
      if (!placed.showLabel) {
        continue;
      }
      final spec = Balance.storeSpecs[placed.label];
      if (spec == null) {
        continue;
      }

      final range = switch (type) {
        VehicleType.sedan => spec.sedanRange,
        VehicleType.truck => spec.truckRange,
        VehicleType.bus => spec.busRange,
      };
      minModifier += range.min;
      maxModifier += range.max;
    }
    return VehicleDemandRange(min: minModifier, max: maxModifier);
  }

  int _randomizedCount(VehicleDemandRange range) {
    final sampled =
        range.min + (_random.nextDouble() * (range.max - range.min));
    return _probabilisticRound(sampled);
  }

  int _probabilisticRound(double value) {
    final lower = value.floor();
    final fraction = value - lower;
    return _random.nextDouble() < fraction ? lower + 1 : lower;
  }

  void _spawnScheduledVehicles({
    required double windowStartMinute,
    required double windowEndMinute,
  }) {
    while (_dailyArrivals.isNotEmpty &&
        _dailyArrivals.first.spawnMinute <= windowStartMinute) {
      _dailyArrivals.removeAt(0);
    }

    if (_dailyArrivals.isEmpty) {
      return;
    }

    final arrival = _dailyArrivals.first;
    if (arrival.spawnMinute > windowEndMinute) {
      return;
    }

    _dailyArrivals.removeAt(0);
    if (!_spawnVehicle(arrival.type)) {
      _dailyArrivals.add(
        DailyArrival(
          type: arrival.type,
          spawnMinute: _elapsedGameMinutes + 5,
        ),
      );
      _dailyArrivals.sort((a, b) => a.spawnMinute.compareTo(b.spawnMinute));
    }
  }

  bool _spawnVehicle(VehicleType type) {
    final slot = _availableParkingSlot();
    if (slot != null && !_hasQueuedVehicles) {
      final route = _routeForParkingSlot(slot);
      if (_isSpawnOccupied(route.first)) {
        return false;
      }
      final vehicle = MovingVehicle(
        id: _nextVehicleId++,
        type: type,
        position: route.first,
        route: route.sublist(1),
        state: VehicleState.arriving,
        parkingSlot: slot,
        parkUntilMinute: 0,
        queueStartMinute: 0,
        queueLane: null,
      );
      slot.reservedBy = vehicle;
      _vehicles.add(vehicle);
      return true;
    }

    final queueLane = _bestQueueLane();
    if (queueLane != null) {
      final queueTileNumber = _nextFreeQueueTile(queueLane)!;
      final route = _routeByTileNumbers(
        queueLane == QueueLane.left
            ? [spawnLeftTileNumber, laneLeftTileNumber, queueTileNumber]
            : [spawnRightTileNumber, laneRightTileNumber, queueTileNumber],
      );
      if (_isSpawnOccupied(route.first)) {
        return false;
      }
      final vehicle = MovingVehicle(
        id: _nextVehicleId++,
        type: type,
        position: route.first,
        route: route.sublist(1),
        state: VehicleState.queueing,
        parkingSlot: null,
        parkUntilMinute: 0,
        queueTileNumber: queueTileNumber,
        queueStartMinute: _elapsedGameMinutes,
        queueLane: queueLane,
      );
      _vehicles.add(vehicle);
      return true;
    }

    final throughRoute = _throughRoute();
    if (_isSpawnOccupied(throughRoute.first)) {
      return false;
    }
    _registerLostVehicle(throughRoute.first);
    _vehicles.add(
      MovingVehicle(
        id: _nextVehicleId++,
        type: type,
        position: throughRoute.first,
        route: throughRoute.sublist(1),
        state: VehicleState.passingThrough,
        parkingSlot: null,
        parkUntilMinute: 0,
        queueStartMinute: 0,
        queueLane: null,
      ),
    );
    return true;
  }

  void _updateVehicles(double dt) {
    final completed = <MovingVehicle>[];
    for (final vehicle in _vehicles) {
      vehicle.lastProgressMinute ??= _elapsedGameMinutes;
      if (vehicle.state == VehicleState.parked) {
        if (_elapsedGameMinutes >= vehicle.parkUntilMinute) {
          _people.removeWhere((person) => person.vehicleId == vehicle.id);
          vehicle.route = _exitRouteFor(vehicle.parkingSlot!);
          vehicle.state = VehicleState.exiting;
          vehicle.parkingSlot!.occupiedBy = null;
          vehicle.parkingSlot!.reservedBy = null;
          vehicle.parkingSlot = null;
        }
        continue;
      }

      if (vehicle.route.isEmpty) {
        if (vehicle.state == VehicleState.arriving) {
          vehicle.state = VehicleState.parked;
          vehicle.parkUntilMinute =
              _elapsedGameMinutes + Balance.parkDurationMinutes;
          vehicle.parkingSlot!.occupiedBy = vehicle;
          vehicle.parkingSlot!.reservedBy = null;
          _playSound(GameSound.vehicleArrive);
          _spawnPeopleForVehicle(vehicle);
          _registerServedVehicle();
        } else if (vehicle.state == VehicleState.exiting ||
            vehicle.state == VehicleState.passingThrough) {
          completed.add(vehicle);
        }
        continue;
      }

      final before = vehicle.position;
      final target = vehicle.route.first;
      final delta = target - vehicle.position;
      final maxStep = vehicle.type.speed * dt;
      if (delta.distance <= maxStep) {
        if (!_isVehicleBlocked(vehicle, target)) {
          vehicle.position = target;
          vehicle.route.removeAt(0);
        }
      } else {
        final nextPosition =
            vehicle.position + delta / delta.distance * maxStep;
        if (!_isVehicleBlocked(vehicle, nextPosition)) {
          vehicle.position = nextPosition;
        }
      }

      if (vehicle.position != before) {
        vehicle.lastProgressMinute = _elapsedGameMinutes;
      } else if (vehicle.state != VehicleState.queueing &&
          _elapsedGameMinutes - vehicle.lastProgressMinute! >=
              Balance.gridlockGiveUpMinutes) {
        // 교착 해소: 대기열이 아닌데 오래 못 나아간 차량을 강제 정리해
        // 코리도 흐름을 되살린다. 예약 슬롯이 있으면 반납한다.
        vehicle.parkingSlot?.reservedBy = null;
        completed.add(vehicle);
      }
    }

    for (final vehicle in completed) {
      _vehicles.remove(vehicle);
      _people.removeWhere((person) => person.vehicleId == vehicle.id);
    }
  }

  void _updatePeople(double dt) {
    final completed = <WalkingPerson>[];
    for (final person in _people) {
      if (person.state == PersonState.dwell) {
        if (_elapsedGameMinutes >= person.dwellUntilMinute) {
          person.state = PersonState.returning;
          person.route = List<Offset>.from(person.returnRoute);
        }
        continue;
      }

      if (person.route.isEmpty) {
        if (person.state == PersonState.outbound) {
          person.state = PersonState.dwell;
          person.dwellUntilMinute = _elapsedGameMinutes + person.visitMinutes;
          if (person.targetStoreAnchorTileNumber != null) {
            _recordSaleAt(person.targetStoreAnchorTileNumber!);
          }
        } else {
          completed.add(person);
        }
        continue;
      }

      final target = person.route.first;
      final delta = target - person.position;
      final maxStep = person.speed * dt;
      if (delta.distance <= maxStep) {
        person.position = target;
        person.route.removeAt(0);
      } else {
        person.position = person.position + (delta / delta.distance) * maxStep;
      }
    }

    for (final person in completed) {
      _people.remove(person);
    }
  }

  void _spawnPeopleForVehicle(MovingVehicle vehicle) {
    final slot = vehicle.parkingSlot;
    if (slot == null) {
      return;
    }

    // 도달 가능한 매장 목록에서 승객마다 각자 방문할 매장을 고른다.
    // 매장이 하나도 없으면 기존처럼 가장 가까운 빈 상업 타일로 산책만 보낸다.
    final storePlans = _reachableStorePlans(slot.spotTileNumber);
    List<int>? walkOnlyPath;
    if (storePlans.isEmpty) {
      final destination = _pickWalkingDestinationTile(slot.spotTileNumber);
      if (destination == null) {
        return;
      }
      walkOnlyPath = _findPedestrianRouteToCommercial(
        startTileNumber: slot.spotTileNumber,
        targetTileNumber: destination,
      );
      if (walkOnlyPath == null || walkOnlyPath.length < 2) {
        return;
      }
    }

    final peopleCount = _passengerCountFor(vehicle.type);
    final availableTypes = _availablePersonTypes(vehicle.type);
    for (var i = 0; i < peopleCount; i++) {
      final plan = storePlans.isEmpty
          ? null
          : _pickWeightedStorePlan(storePlans, vehicle.type);
      final pathToDestination = plan?.path ?? walkOnlyPath!;
      final personType = availableTypes[_random.nextInt(availableTypes.length)];
      final startPosition = _tileCenterByNumber(slot.spotTileNumber) +
          Offset(
            (_random.nextDouble() * pedestrianSpawnJitter * 2) -
                pedestrianSpawnJitter,
            (_random.nextDouble() * pedestrianSpawnJitter * 2) -
                pedestrianSpawnJitter,
          );
      final outboundRoute = _offsetPedestrianRoute(pathToDestination);
      final returnRoute =
          _offsetPedestrianRoute(pathToDestination.reversed.toList());
      _people.add(
        WalkingPerson(
          id: _nextPersonId++,
          vehicleId: vehicle.id,
          type: personType,
          position: startPosition,
          route: List<Offset>.from(outboundRoute),
          returnRoute: returnRoute,
          state: PersonState.outbound,
          targetStoreAnchorTileNumber: plan?.anchorTileNumber,
          visitMinutes: Balance.visitMinutesMin +
              _random.nextInt(
                Balance.visitMinutesMax - Balance.visitMinutesMin + 1,
              ),
          dwellUntilMinute: 0,
          speed: 34 + (_random.nextDouble() * 10),
        ),
      );
    }
  }

  /// 차량 유형 기준 매장 선호 가중치 = 해당 유형 수요 범위의 중간값.
  /// 모든 매장은 최소 [Balance.minStoreAffinity]의 가중치를 보장받는다.
  double _storeWeightFor(String storeName, VehicleType type) {
    final spec = Balance.storeSpecs[storeName];
    if (spec == null) {
      return 0;
    }
    final range = switch (type) {
      VehicleType.sedan => spec.sedanRange,
      VehicleType.truck => spec.truckRange,
      VehicleType.bus => spec.busRange,
    };
    return math.max((range.min + range.max) / 2, Balance.minStoreAffinity);
  }

  /// 선호 가중치에 비례해 방문할 매장을 고른다(룰렛 휠 방식).
  StoreVisitPlan _pickWeightedStorePlan(
    List<StoreVisitPlan> plans,
    VehicleType type,
  ) {
    var total = 0.0;
    final weights = <double>[];
    for (final plan in plans) {
      final weight = _storeWeightFor(plan.storeName, type);
      weights.add(weight);
      total += weight;
    }
    if (total <= 0) {
      return plans[_random.nextInt(plans.length)];
    }

    var roll = _random.nextDouble() * total;
    for (var i = 0; i < plans.length; i++) {
      roll -= weights[i];
      if (roll <= 0) {
        return plans[i];
      }
    }
    return plans.last;
  }

  /// 배치된 매장 중 하나를 무작위로 골라 방문 계획을 세운다.
  /// 도달 가능한 매장이 없으면 null.
  StoreVisitPlan? _planStoreVisit(int startTileNumber) {
    final plans = _reachableStorePlans(startTileNumber);
    if (plans.isEmpty) {
      return null;
    }
    return plans[_random.nextInt(plans.length)];
  }

  /// 주차 지점에서 도달 가능한 모든 매장의 방문 계획 목록.
  /// 승객 개인별 매장 선택에 쓰인다(매장당 BFS 1회).
  List<StoreVisitPlan> _reachableStorePlans(int startTileNumber) {
    final plans = <StoreVisitPlan>[];
    for (final entry in _placedTiles.entries) {
      if (!entry.value.showLabel ||
          !Balance.storeSpecs.containsKey(entry.value.label)) {
        continue;
      }
      for (final frontTile in _storeFrontTiles(entry.key, entry.value.label)) {
        final path = _findPedestrianRouteToCommercial(
          startTileNumber: startTileNumber,
          targetTileNumber: frontTile,
        );
        if (path != null && path.length >= 2) {
          plans.add(
            (
              storeName: entry.value.label,
              anchorTileNumber: entry.key,
              path: path,
            ),
          );
          break; // 이 매장은 경로 확보 완료, 다음 매장으로
        }
      }
    }
    return plans;
  }

  /// 매장 발자국(앵커 + 아래 타일)에 인접한 보행 가능 타일 목록.
  List<int> _storeFrontTiles(int anchorTileNumber, String label) {
    final anchorTile = _tileByNumber[anchorTileNumber];
    if (anchorTile == null) {
      return const [];
    }

    final footprint = <MapTile>[anchorTile];
    final below = _tileAt(
      logicalX: anchorTile.logicalX,
      logicalY: anchorTile.logicalY + 1,
    );
    if (below != null && _placedTiles[below.tileNumber]?.label == label) {
      footprint.add(below);
    }

    final fronts = <int>[];
    final seen = <int>{};
    for (final tile in footprint) {
      for (final neighbor in _neighborTileNumbers(tile)) {
        if (!seen.add(neighbor)) {
          continue;
        }
        final neighborTile = _tileByNumber[neighbor]!;
        if (neighborTile.zone == TileZone.parking ||
            _isPedestrianCommercialTile(neighbor)) {
          fronts.add(neighbor);
        }
      }
    }
    return fronts;
  }

  /// 앵커 타일의 매장에서 1인 구매 발생. 매장 레벨·직원 보너스가 반영된다.
  void _recordSaleAt(int anchorTileNumber) {
    final placed = _placedTiles[anchorTileNumber];
    if (placed == null) {
      return;
    }
    final salePrice = Balance.salePriceWith(
      placed.label,
      placed.level,
      placed.staffCount,
    );
    if (salePrice == null) {
      return;
    }
    _money += salePrice;
    moneyLabel.value = _formatMoney(_money);
    _playSound(GameSound.sale);
    _floatingSaleTexts.add(
      FloatingSaleText(
        position: _tileCenterByNumber(anchorTileNumber) - const Offset(0, 16),
        text: '+${_formatNumber(salePrice)}원',
      ),
    );
    _bumpQuestStat(QuestMetric.salesCount);
  }

  int? _pickWalkingDestinationTile(int startTileNumber) {
    final startTile = _tileByNumber[startTileNumber];
    if (startTile == null) {
      return null;
    }

    final queue = <int>[startTileNumber];
    final visited = <int>{startTileNumber};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentTile = _tileByNumber[current]!;
      for (final neighbor in _neighborTileNumbers(currentTile)) {
        if (!visited.add(neighbor)) {
          continue;
        }

        if (_isPedestrianCommercialTile(neighbor)) {
          return neighbor;
        }

        final neighborTile = _tileByNumber[neighbor];
        if (neighborTile?.zone == TileZone.parking) {
          queue.add(neighbor);
        }
      }
    }

    return null;
  }

  int _passengerCountFor(VehicleType type) {
    switch (type) {
      case VehicleType.sedan:
        final roll = _random.nextDouble();
        if (roll < 0.55) return 1;
        if (roll < 0.82) return 2;
        if (roll < 0.95) return 3;
        return 4;
      case VehicleType.truck:
        return _random.nextDouble() < 0.8 ? 1 : 2;
      case VehicleType.bus:
        return 8 + _random.nextInt(8);
    }
  }

  List<PersonType> _availablePersonTypes(VehicleType type) {
    switch (type) {
      case VehicleType.truck:
        return const [PersonType.man, PersonType.woman];
      case VehicleType.sedan:
      case VehicleType.bus:
        return PersonType.values;
    }
  }

  List<int>? _findPedestrianRouteToCommercial({
    required int startTileNumber,
    required int targetTileNumber,
  }) {
    final startTile = _tileByNumber[startTileNumber];
    final targetTile = _tileByNumber[targetTileNumber];
    if (startTile == null || targetTile == null) {
      return null;
    }

    final queue = <int>[startTileNumber];
    final previous = <int, int?>{startTileNumber: null};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      if (current == targetTileNumber) {
        break;
      }

      final currentTile = _tileByNumber[current]!;
      for (final neighbor in _neighborTileNumbers(currentTile)) {
        if (previous.containsKey(neighbor)) {
          continue;
        }
        if (!_isPedestrianEntryPassable(neighbor, targetTileNumber)) {
          continue;
        }
        previous[neighbor] = current;
        queue.add(neighbor);
      }
    }

    if (!previous.containsKey(targetTileNumber)) {
      return null;
    }

    final path = <int>[];
    int? cursor = targetTileNumber;
    while (cursor != null) {
      path.add(cursor);
      cursor = previous[cursor];
    }
    return path.reversed.toList();
  }

  Iterable<int> _neighborTileNumbers(MapTile tile) sync* {
    final candidates = [
      (tile.logicalX + 1, tile.logicalY),
      (tile.logicalX - 1, tile.logicalY),
      (tile.logicalX, tile.logicalY + 1),
      (tile.logicalX, tile.logicalY - 1),
    ];
    for (final candidate in candidates) {
      final neighbor = _tileAt(logicalX: candidate.$1, logicalY: candidate.$2);
      if (neighbor != null) {
        yield neighbor.tileNumber;
      }
    }
  }

  bool _isPedestrianEntryPassable(int tileNumber, int targetTileNumber) {
    if (tileNumber == targetTileNumber) {
      return true;
    }
    final tile = _tileByNumber[tileNumber];
    if (tile == null) {
      return false;
    }
    if (tile.zone == TileZone.parking) {
      return true;
    }
    return _isPedestrianCommercialTile(tileNumber);
  }

  bool _isPedestrianCommercialTile(int tileNumber) {
    final tile = _tileByNumber[tileNumber];
    if (tile == null || tile.zone != TileZone.commercial) {
      return false;
    }
    if (_treeTileNumbers.contains(tileNumber)) {
      return false;
    }
    if (_placedTiles.containsKey(tileNumber)) {
      return false;
    }
    if (restroomTileNumbers.contains(tileNumber)) {
      return false;
    }
    return true;
  }

  List<Offset> _offsetPedestrianRoute(List<int> tileNumbers) {
    if (tileNumbers.length < 2) {
      return [_tileCenterByNumber(tileNumbers.first)];
    }

    final result = <Offset>[];
    for (var i = 1; i < tileNumbers.length; i++) {
      final previous = _tileCenterByNumber(tileNumbers[i - 1]);
      final current = _tileCenterByNumber(tileNumbers[i]);
      final direction = current - previous;
      if (direction.distance == 0) {
        result.add(current);
        continue;
      }
      final normal = Offset(direction.dy, -direction.dx) / direction.distance;
      result.add(current + (normal * pedestrianSideOffset));
    }
    return result;
  }

  void _promoteQueuedVehicles() {
    final queuedVehicles = _vehicles
        .where((vehicle) => vehicle.state == VehicleState.queueing)
        .toList();
    for (final vehicle in queuedVehicles) {
      if (_elapsedGameMinutes - vehicle.queueStartMinute >=
          Balance.queueGiveUpMinutes) {
        vehicle.route = _queuePassThroughRoute();
        vehicle.state = VehicleState.passingThrough;
        vehicle.lastProgressMinute = _elapsedGameMinutes;
        _registerLostVehicle(vehicle.position);
        vehicle.queueTileNumber = null;
        vehicle.queueLane = null;
      }
    }

    _shiftQueueLane(QueueLane.left);
    _shiftQueueLane(QueueLane.right);

    _promoteFrontQueuedVehicle(QueueLane.left);
    _promoteFrontQueuedVehicle(QueueLane.right);
  }

  ParkingSlot? _availableParkingSlot() {
    for (final slot in _parkingSlots) {
      if (slot.occupiedBy == null && slot.reservedBy == null) {
        return slot;
      }
    }
    return null;
  }

  bool get _hasQueuedVehicles =>
      _vehicles.any((vehicle) => vehicle.state == VehicleState.queueing);

  QueueLane? _bestQueueLane() {
    final leftFree = _nextFreeQueueTile(QueueLane.left);
    final rightFree = _nextFreeQueueTile(QueueLane.right);
    if (leftFree == null && rightFree == null) {
      return null;
    }
    if (leftFree != null && rightFree == null) {
      return QueueLane.left;
    }
    if (leftFree == null && rightFree != null) {
      return QueueLane.right;
    }

    final leftCount = _queuedVehiclesForLane(QueueLane.left).length;
    final rightCount = _queuedVehiclesForLane(QueueLane.right).length;
    return leftCount <= rightCount ? QueueLane.left : QueueLane.right;
  }

  int? _nextFreeQueueTile(QueueLane lane) {
    for (final tileNumber in _queueTileNumbersFor(lane)) {
      final occupied = _vehicles.any(
        (vehicle) =>
            vehicle.state == VehicleState.queueing &&
            vehicle.queueTileNumber == tileNumber,
      );
      if (!occupied) {
        return tileNumber;
      }
    }
    return null;
  }

  List<MovingVehicle> _queuedVehiclesForLane(QueueLane lane) {
    return _vehicles
        .where(
          (vehicle) =>
              vehicle.state == VehicleState.queueing &&
              vehicle.queueLane == lane,
        )
        .toList()
      ..sort(
        (a, b) => _queueTileNumbersFor(lane)
            .indexOf(a.queueTileNumber!)
            .compareTo(_queueTileNumbersFor(lane).indexOf(b.queueTileNumber!)),
      );
  }

  List<int> _queueTileNumbersFor(QueueLane lane) {
    return lane == QueueLane.left
        ? leftQueueTileNumbers
        : rightQueueTileNumbers;
  }

  void _shiftQueueLane(QueueLane lane) {
    final queueTiles = _queueTileNumbersFor(lane);
    final queuedVehicles = _queuedVehiclesForLane(lane);
    for (var i = 0; i < queuedVehicles.length; i++) {
      final vehicle = queuedVehicles[i];
      final targetTile = queueTiles[i];
      if (vehicle.queueTileNumber == targetTile) {
        continue;
      }
      vehicle.queueTileNumber = targetTile;
      vehicle.route = _routeByTileNumbers([targetTile]);
    }
  }

  void _promoteFrontQueuedVehicle(QueueLane lane) {
    final queueTiles = _queueTileNumbersFor(lane);
    final queuedVehicles = _queuedVehiclesForLane(lane);
    if (queuedVehicles.isEmpty) {
      return;
    }

    final frontVehicle = queuedVehicles.first;
    if (frontVehicle.queueTileNumber != queueTiles.first) {
      return;
    }

    // 차선 쪽 기본 슬롯을 우선하되, 차 있으면 확장 슬롯 등 아무 빈 슬롯으로.
    final preferredSlot = lane == QueueLane.left
        ? _parkingSlotByNumber(2092)
        : _parkingSlotByNumber(2121);
    final slot = (preferredSlot != null &&
            preferredSlot.occupiedBy == null &&
            preferredSlot.reservedBy == null)
        ? preferredSlot
        : _availableParkingSlot();
    if (slot == null) {
      return;
    }

    frontVehicle.parkingSlot = slot;
    slot.reservedBy = frontVehicle;
    frontVehicle.route =
        _routeFromQueueToParking(frontVehicle.queueTileNumber!, slot);
    frontVehicle.state = VehicleState.arriving;
    frontVehicle.lastProgressMinute = _elapsedGameMinutes;
    frontVehicle.queueTileNumber = null;
    frontVehicle.queueLane = null;
  }

  ParkingSlot? _parkingSlotByNumber(int spotTileNumber) {
    for (final slot in _parkingSlots) {
      if (slot.spotTileNumber == spotTileNumber) {
        return slot;
      }
    }
    return null;
  }

  List<Offset> _routeForParkingSlot(ParkingSlot slot) {
    if (slot.spotTileNumber == 2121) {
      return _routeByTileNumbers([
        spawnRightTileNumber,
        laneRightTileNumber,
        2202,
        2175,
        2149,
        2122,
        2093,
        2121,
      ]);
    }
    if (slot.spotTileNumber == 2092) {
      return _routeByTileNumbers([
        spawnLeftTileNumber,
        laneLeftTileNumber,
        2176,
        2149,
        2122,
        2093,
        2063,
        2092,
      ]);
    }

    // 확장 주차 슬롯: 고정 진입 구간(스폰 → 분기점) 뒤에 BFS 경로를 잇는다.
    final entryPrefix = _random.nextBool()
        ? const [
            spawnRightTileNumber,
            laneRightTileNumber,
            2202,
            2175,
            2149,
            2122,
            parkingJunctionTileNumber,
          ]
        : const [
            spawnLeftTileNumber,
            laneLeftTileNumber,
            2176,
            2149,
            2122,
            parkingJunctionTileNumber,
          ];
    final branch = _vehicleTilePathBetween(
          fromTileNumber: parkingJunctionTileNumber,
          toTileNumber: slot.spotTileNumber,
        ) ??
        [
          parkingJunctionTileNumber,
          slot.approachTileNumber,
          slot.spotTileNumber,
        ];
    return _routeByTileNumbers([...entryPrefix, ...branch.sublist(1)]);
  }

  List<Offset> _routeFromQueueToParking(int queueTileNumber, ParkingSlot slot) {
    if (queueTileNumber == 2202 && slot.spotTileNumber == 2121) {
      return _routeByTileNumbers([2175, 2149, 2122, 2093, 2121]);
    }
    if (queueTileNumber == 2176 && slot.spotTileNumber == 2092) {
      return _routeByTileNumbers([2149, 2122, 2093, 2063, 2092]);
    }
    final path = _vehicleTilePathBetween(
      fromTileNumber: queueTileNumber,
      toTileNumber: slot.spotTileNumber,
    );
    if (path != null && path.length >= 2) {
      return _routeByTileNumbers(path.sublist(1));
    }
    return _routeByTileNumbers([slot.approachTileNumber, slot.spotTileNumber]);
  }

  List<Offset> _exitRouteFor(ParkingSlot slot) {
    if (slot.spotTileNumber == 2121) {
      return _routeByTileNumbers([2093, 2064, 2033, 2001, 2000]);
    }
    if (slot.spotTileNumber == 2092) {
      return _routeByTileNumbers([2063, 2033, 2001, 2000]);
    }

    // 확장 주차 슬롯: 출차 합류점까지 BFS 후 기존 출차 코리도를 잇는다.
    final toExit = _vehicleTilePathBetween(
      fromTileNumber: slot.spotTileNumber,
      toTileNumber: exitJunctionTileNumber,
    );
    if (toExit == null || toExit.length < 2) {
      return _routeByTileNumbers(
        [slot.approachTileNumber, exitJunctionTileNumber, 2001, 2000],
      );
    }
    return _routeByTileNumbers([...toExit.sublist(1), 2001, 2000]);
  }

  List<Offset> _throughRoute() {
    return _routeByTileNumbers(
      _random.nextBool()
          ? [
              spawnRightTileNumber,
              laneRightTileNumber,
              2202,
              2175,
              2149,
              2122,
              2093,
              2064,
              2033,
              2001,
              2000,
            ]
          : [
              spawnLeftTileNumber,
              laneLeftTileNumber,
              2176,
              2149,
              2122,
              2093,
              2064,
              2033,
              2001,
              2000,
            ],
    );
  }

  List<Offset> _queuePassThroughRoute() {
    return _routeByTileNumbers([2093, 2064, 2033, 2001, 2000]);
  }

  List<Offset> _routeByTileNumbers(List<int> tileNumbers) {
    return tileNumbers.map(_tileCenterByNumber).toList();
  }

  bool _isVehicleBlocked(MovingVehicle vehicle, Offset nextPosition) {
    for (final other in _vehicles) {
      if (identical(vehicle, other)) {
        continue;
      }
      if ((other.position - nextPosition).distance < vehicleSpacing) {
        return true;
      }
    }
    return false;
  }

  bool _isSpawnOccupied(Offset point) {
    for (final vehicle in _vehicles) {
      if ((vehicle.position - point).distance < vehicleSpacing) {
        return true;
      }
    }
    return false;
  }

  Offset _tileCenterByNumber(int tileNumber) {
    return _tileByNumber[tileNumber]!.center;
  }

  static String _formatGameTime(int totalMinutes) {
    final minutesIntoYear = totalMinutes % gameMinutesPerYear;
    const minutesPerMonth = 30 * 24 * 60;
    const minutesPerDay = 24 * 60;
    final month = (minutesIntoYear ~/ minutesPerMonth) + 1;
    final minutesIntoMonth = minutesIntoYear % minutesPerMonth;
    final day = (minutesIntoMonth ~/ minutesPerDay) + 1;
    final minutesIntoDay = minutesIntoMonth % minutesPerDay;
    final hour = minutesIntoDay ~/ 60;
    final minute = minutesIntoDay % 60;
    return '$month월 $day일 $hour시 ${minute.toString().padLeft(2, '0')}분';
  }

  static String _formatClockOnly(double totalMinutes) {
    final snappedMinutes = totalMinutes.floor();
    final minutesIntoDay = snappedMinutes % gameMinutesPerDay;
    final hour = minutesIntoDay ~/ 60;
    final minute = minutesIntoDay % 60;
    return '$hour시 ${minute.toString().padLeft(2, '0')}분';
  }

  static String _formatMoney(int amount) => '자금 ${_formatNumber(amount)}원';

  static String _formatNumber(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final indexFromEnd = digits.length - i;
      buffer.write(digits[i]);
      if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

class PlacedTileData {
  const PlacedTileData({
    required this.label,
    required this.backgroundColor,
    required this.showLabel,
    this.level = 1,
    this.staffCount = 0,
  });

  final String label;
  final Color backgroundColor;
  final bool showLabel;

  /// 매장 레벨. 앵커 타일(showLabel == true)의 값만 의미가 있다.
  final int level;

  /// 고용된 직원 수. 앵커 타일의 값만 의미가 있다.
  final int staffCount;
}

/// 구매 발생 시 매장 위로 떠오르는 "+N원" 텍스트.
class FloatingSaleText {
  FloatingSaleText({
    required this.position,
    required this.text,
    this.color = const Color(0xFFFFE082),
  });

  Offset position;
  final String text;
  final Color color;
  double age = 0;
}

/// 재접속 시 오프라인 정산 결과(다이얼로그 표시용).
class OfflineEarningsReport {
  const OfflineEarningsReport({
    required this.amount,
    required this.offlineGameDays,
  });

  final int amount;
  final double offlineGameDays;
}

/// 배치된 매장을 탭했을 때 UI에 전달되는 업그레이드 요청 정보.
class StoreUpgradeRequest {
  const StoreUpgradeRequest({
    required this.anchorTileNumber,
    required this.storeName,
    required this.level,
    required this.currentSalePrice,
    required this.nextSalePrice,
    required this.upgradeCost,
    required this.staffCount,
    required this.staffHireCost,
  });

  final int anchorTileNumber;
  final String storeName;
  final int level;
  final int currentSalePrice;

  /// 최대 레벨이면 null.
  final int? nextSalePrice;

  /// 최대 레벨이면 null.
  final int? upgradeCost;

  /// 고용된 직원 수.
  final int staffCount;

  /// 다음 직원 고용 비용. 최대 인원이면 null.
  final int? staffHireCost;
}

/// 잠긴 부지 탭 시 UI에 전달되는 해금 요청 정보.
class LandUnlockRequest {
  const LandUnlockRequest({required this.plotKey, required this.cost});

  final int plotKey;
  final int cost;
}

class DailyArrival {
  const DailyArrival({
    required this.type,
    required this.spawnMinute,
  });

  final VehicleType type;
  final double spawnMinute;
}

/// 방문 계획: 방문할 매장(이름·앵커 타일)과 주차 지점→매장 앞 타일 번호 경로.
typedef StoreVisitPlan = ({
  String storeName,
  int anchorTileNumber,
  List<int> path,
});

class ParkingSlot {
  ParkingSlot({
    required this.spotTileNumber,
    required this.approachTileNumber,
  });

  final int spotTileNumber;
  final int approachTileNumber;
  MovingVehicle? occupiedBy;
  MovingVehicle? reservedBy;
}

class MovingVehicle {
  MovingVehicle({
    required this.id,
    required this.type,
    required this.position,
    required this.route,
    required this.state,
    required this.parkingSlot,
    required this.parkUntilMinute,
    required this.queueStartMinute,
    this.queueTileNumber,
    required this.queueLane,
  });

  final int id;
  final VehicleType type;
  Offset position;
  List<Offset> route;
  VehicleState state;
  ParkingSlot? parkingSlot;
  double parkUntilMinute;
  double queueStartMinute;
  int? queueTileNumber;
  QueueLane? queueLane;

  /// 마지막으로 위치가 전진한 게임 분. 대기열 제외 상태에서 이 값이
  /// 오래 갱신되지 않으면 교착으로 간주해 강제 정리한다. null이면 첫 업데이트에서 초기화.
  double? lastProgressMinute;
}

class WalkingPerson {
  WalkingPerson({
    required this.id,
    required this.vehicleId,
    required this.type,
    required this.position,
    required this.route,
    required this.returnRoute,
    required this.state,
    this.targetStoreAnchorTileNumber,
    required this.visitMinutes,
    required this.dwellUntilMinute,
    required this.speed,
  });

  final int id;
  final int vehicleId;
  final PersonType type;
  Offset position;
  List<Offset> route;
  final List<Offset> returnRoute;
  PersonState state;

  /// 방문(구매) 대상 매장의 앵커 타일 번호. null이면 산책만 하고 매출이 없다.
  final int? targetStoreAnchorTileNumber;
  final int visitMinutes;
  double dwellUntilMinute;
  final double speed;
}

class MapTile {
  MapTile({
    required this.logicalX,
    required this.logicalY,
    required this.zone,
    required this.center,
  })  : path = Path()
          ..moveTo(center.dx, center.dy - HighwayTycoonGame.tileHalfHeight)
          ..lineTo(center.dx + HighwayTycoonGame.tileHalfWidth, center.dy)
          ..lineTo(center.dx, center.dy + HighwayTycoonGame.tileHalfHeight)
          ..lineTo(center.dx - HighwayTycoonGame.tileHalfWidth, center.dy)
          ..close(),
        bounds = Rect.fromLTWH(
          center.dx - HighwayTycoonGame.tileHalfWidth,
          center.dy - HighwayTycoonGame.tileHalfHeight,
          HighwayTycoonGame.tileHalfWidth * 2,
          HighwayTycoonGame.tileHalfHeight * 2,
        );

  final int logicalX;
  final int logicalY;
  final TileZone zone;
  final Offset center;
  final Path path;
  final Rect bounds;
  int tileNumber = 0;

  late final TextPainter smallNumberPainter = TextPainter(
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 1,
  );

  late final TextPainter largeNumberPainter = TextPainter(
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 1,
  );

  void updateNumberPainters() {
    smallNumberPainter
      ..text = TextSpan(
        text: '$tileNumber',
        style: const TextStyle(
          color: Color(0xFF231A10),
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      )
      ..layout(maxWidth: HighwayTycoonGame.tileHalfWidth * 1.6);
    largeNumberPainter
      ..text = TextSpan(
        text: '$tileNumber',
        style: const TextStyle(
          color: Color(0xFF231A10),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      )
      ..layout(maxWidth: HighwayTycoonGame.tileHalfWidth * 1.6);
  }
}

class _SpecialLabelPainters {
  const _SpecialLabelPainters({
    required this.label,
    required this.number,
  });

  final TextPainter label;
  final TextPainter number;
}

enum TileZone {
  parking,
  commercial,
}

enum VehicleState {
  arriving,
  queueing,
  parked,
  exiting,
  passingThrough,
}

enum QueueLane {
  left,
  right,
}

enum VehicleType {
  sedan(color: Color(0xFF2E73FF), speed: 92),
  truck(color: Color(0xFFD94242), speed: 84),
  bus(color: Color(0xFFE5C643), speed: 78);

  const VehicleType({
    required this.color,
    required this.speed,
  });

  final Color color;
  final double speed;

  String get label => switch (this) {
        VehicleType.sedan => '세단',
        VehicleType.truck => '트럭',
        VehicleType.bus => '버스',
      };
}

enum PersonState {
  outbound,
  dwell,
  returning,
}

enum PersonShape {
  circle,
  triangle,
  square,
  star,
}

enum PersonType {
  man(color: Color(0xFF2E73FF), shape: PersonShape.circle),
  woman(color: Color(0xFFD94242), shape: PersonShape.circle),
  boyBaby(color: Color(0xFF2E73FF), shape: PersonShape.triangle),
  girlBaby(color: Color(0xFFD94242), shape: PersonShape.triangle),
  grandfather(color: Color(0xFF2E73FF), shape: PersonShape.square),
  grandmother(color: Color(0xFFD94242), shape: PersonShape.square),
  boyStudent(color: Color(0xFF2E73FF), shape: PersonShape.star),
  girlStudent(color: Color(0xFFD94242), shape: PersonShape.star);

  const PersonType({
    required this.color,
    required this.shape,
  });

  final Color color;
  final PersonShape shape;
}
