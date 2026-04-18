import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

class HighwayTycoonGame extends FlameGame {
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
  static const double minZoom = 0.45;
  static const double maxZoom = 2.6;
  static const double tileHalfWidth = 42;
  static const double tileHalfHeight = 22;
  static const double cameraMargin = 80;
  static const double vehicleSpacing = 18;
  static const int realSecondsPerGameYear = 172800;
  static const int gameMinutesPerYear = 12 * 30 * 24 * 60;
  static const double gameMinutesPerRealSecond =
      gameMinutesPerYear / realSecondsPerGameYear;
  static const int startingGameMinutes = ((((1 * 30) + 1) * 24 + 12) * 60) + 30;
  static const int gameMinutesPerDay = 24 * 60;
  static const Set<int> restroomTileNumbers = {2173, 2199, 2200, 2226};
  static const Set<int> parkingLabelTileNumbers = {2092, 2121};
  static const Set<int> treeTileNumbers = {2201, 2227, 2252};

  final List<MapTile> _tiles = [];
  final Map<int, PlacedTileData> _placedTiles = {};
  final Map<int, MapTile> _tileByNumber = {};
  final Map<String, _SpecialLabelPainters> _specialLabelPainterCache = {};
  final List<MovingVehicle> _vehicles = [];
  final List<DailyArrival> _dailyArrivals = [];
  final List<ParkingSlot> _parkingSlots = [
    ParkingSlot(spotTileNumber: 2092, approachTileNumber: 2063),
    ParkingSlot(spotTileNumber: 2121, approachTileNumber: 2093),
  ];
  final ValueNotifier<String> timeLabel = ValueNotifier<String>(
    _formatGameTime(startingGameMinutes),
  );
  final math.Random _random = math.Random();

  Offset _cameraCenter = Offset.zero;
  Rect _worldBounds = Rect.zero;
  double _zoom = 1.0;
  String? _pendingPlacementName;
  double _elapsedGameMinutes = startingGameMinutes.toDouble();
  int _currentTrafficDay = -1;

  @override
  Color backgroundColor() => const Color(0xFF698553);

  @override
  FutureOr<void> onLoad() {
    _buildTileMap();
    _rebuildTrafficPlan(force: true);
    _spawnScheduledVehicles();
  }

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
    canvas.restore();
  }

  @override
  void update(double dt) {
    super.update(dt);
    _elapsedGameMinutes += dt * gameMinutesPerRealSecond;
    final snappedMinutes = ((_elapsedGameMinutes ~/ 10) * 10);
    final nextLabel = _formatGameTime(snappedMinutes);
    if (timeLabel.value != nextLabel) {
      timeLabel.value = nextLabel;
    }

    _rebuildTrafficPlan();
    _spawnScheduledVehicles();
    _updateVehicles(dt);
    _promoteQueuedVehicles();
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
  }

  void handleTap(Offset screenPoint) {
    if (_pendingPlacementName == null) {
      return;
    }

    final targetTile = _currentPlacementTile;
    if (targetTile == null) {
      return;
    }

    final worldPoint = _screenToWorld(screenPoint, _zoom);
    if (!targetTile.path.contains(worldPoint)) {
      return;
    }

    _placedTiles[targetTile.tileNumber] = PlacedTileData(
      label: _pendingPlacementName!,
      backgroundColor: const Color(0xFF111111),
    );
    _pendingPlacementName = null;
  }

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

    for (final tile in _tiles) {
      if (!tile.bounds.overlaps(drawViewport)) {
        continue;
      }

      canvas.drawPath(tile.path, Paint()..color = _tileColor(tile));
      canvas.drawPath(tile.path, borderPaint);
      if (placementTile?.tileNumber == tile.tileNumber) {
        canvas.drawPath(
          tile.path,
          Paint()..color = const Color(0xFF808080),
        );
        canvas.drawPath(tile.path, borderPaint);
      }

      final placedData = _placedTiles[tile.tileNumber];
      final specialLabel = _specialLabelFor(tile);
      if (placedData != null) {
        _drawSpecialLabel(
          canvas,
          tile,
          placedData.label,
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

  void _drawTileLabel(Canvas canvas, MapTile tile) {
    if (_zoom < 0.9) {
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
    if (treeTileNumbers.contains(tile.tileNumber)) {
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
    if (treeTileNumbers.contains(tile.tileNumber)) {
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

    MapTile? best;
    var bestDistance = double.infinity;
    for (final tile in _tiles) {
      if (tile.zone != TileZone.commercial) {
        continue;
      }
      if (_specialLabelFor(tile) != null ||
          _placedTiles.containsKey(tile.tileNumber)) {
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

  void _rebuildTrafficPlan({bool force = false}) {
    final day = (_elapsedGameMinutes ~/ gameMinutesPerDay).toInt();
    if (!force && day == _currentTrafficDay) {
      return;
    }

    _currentTrafficDay = day;
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
    switch (type) {
      case VehicleType.sedan:
        return VehicleDemandRange(
          min: 8 + modifier,
          max: 10 + (modifier * 1.3),
        );
      case VehicleType.truck:
        return VehicleDemandRange(
          min: 1 + (modifier * 0.2),
          max: 3 + (modifier * 0.6),
        );
      case VehicleType.bus:
        return VehicleDemandRange(
          min: 0,
          max: 0.5 + (modifier * 0.15),
        );
    }
  }

  double _buildingModifierFor(VehicleType type) {
    var modifier = 0.0;
    for (final placed in _placedTiles.values) {
      switch (type) {
        case VehicleType.sedan:
          if (const {
            '카페',
            '빵집',
            '핫도그',
            '떡볶이',
            '닭강정',
            '호두과자',
            '감자/옥수수',
            '라면',
          }.contains(placed.label)) {
            modifier += 0.25;
          }
        case VehicleType.truck:
          if (const {
            '국밥',
            '백반',
            '설렁탕',
            '불고기',
            '제육볶음',
          }.contains(placed.label)) {
            modifier += 0.18;
          }
        case VehicleType.bus:
          if (const {
            '화장실',
            '백반',
            '국밥',
            '불고기',
          }.contains(placed.label)) {
            modifier += 0.12;
          }
      }
    }
    return modifier;
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

  void _spawnScheduledVehicles() {
    while (_dailyArrivals.isNotEmpty &&
        _dailyArrivals.first.spawnMinute <= _elapsedGameMinutes) {
      final arrival = _dailyArrivals.removeAt(0);
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
  }

  bool _spawnVehicle(VehicleType type) {
    final slot = _availableParkingSlot();
    if (slot != null && !_hasQueuedVehicles) {
      final route = _routeForParkingSlot(slot);
      if (_isSpawnOccupied(route.first)) {
        return false;
      }
      final vehicle = MovingVehicle(
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
    _vehicles.add(
      MovingVehicle(
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
      if (vehicle.state == VehicleState.parked) {
        if (_elapsedGameMinutes >= vehicle.parkUntilMinute) {
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
          vehicle.parkUntilMinute = _elapsedGameMinutes + 60;
          vehicle.parkingSlot!.occupiedBy = vehicle;
          vehicle.parkingSlot!.reservedBy = null;
        } else if (vehicle.state == VehicleState.exiting ||
            vehicle.state == VehicleState.passingThrough) {
          completed.add(vehicle);
        }
        continue;
      }

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
    }

    for (final vehicle in completed) {
      _vehicles.remove(vehicle);
    }
  }

  void _promoteQueuedVehicles() {
    final queuedVehicles = _vehicles
        .where((vehicle) => vehicle.state == VehicleState.queueing)
        .toList();
    for (final vehicle in queuedVehicles) {
      if (_elapsedGameMinutes - vehicle.queueStartMinute >= 60) {
        vehicle.route = _queuePassThroughRoute();
        vehicle.state = VehicleState.passingThrough;
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

    final slot = lane == QueueLane.left
        ? _parkingSlotByNumber(2092)
        : _parkingSlotByNumber(2121);
    if (slot == null || slot.occupiedBy != null || slot.reservedBy != null) {
      return;
    }

    frontVehicle.parkingSlot = slot;
    slot.reservedBy = frontVehicle;
    frontVehicle.route =
        _routeFromQueueToParking(frontVehicle.queueTileNumber!, slot);
    frontVehicle.state = VehicleState.arriving;
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

  List<Offset> _routeFromQueueToParking(int queueTileNumber, ParkingSlot slot) {
    if (queueTileNumber == 2202 && slot.spotTileNumber == 2121) {
      return _routeByTileNumbers([2175, 2149, 2122, 2093, 2121]);
    }
    if (queueTileNumber == 2176 && slot.spotTileNumber == 2092) {
      return _routeByTileNumbers([2149, 2122, 2093, 2063, 2092]);
    }
    return _routeByTileNumbers([slot.approachTileNumber, slot.spotTileNumber]);
  }

  List<Offset> _exitRouteFor(ParkingSlot slot) {
    if (slot.spotTileNumber == 2121) {
      return _routeByTileNumbers([2093, 2064, 2033, 2001, 2000]);
    }
    return _routeByTileNumbers([2063, 2033, 2001, 2000]);
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
}

class PlacedTileData {
  const PlacedTileData({
    required this.label,
    required this.backgroundColor,
  });

  final String label;
  final Color backgroundColor;
}

class DailyArrival {
  const DailyArrival({
    required this.type,
    required this.spawnMinute,
  });

  final VehicleType type;
  final double spawnMinute;
}

class VehicleDemandRange {
  const VehicleDemandRange({
    required this.min,
    required this.max,
  });

  final double min;
  final double max;
}

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

  final VehicleType type;
  Offset position;
  List<Offset> route;
  VehicleState state;
  ParkingSlot? parkingSlot;
  double parkUntilMinute;
  double queueStartMinute;
  int? queueTileNumber;
  QueueLane? queueLane;
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
}
