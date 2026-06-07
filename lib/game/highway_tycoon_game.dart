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
  final Map<String, _SpecialLabelPainters> _specialLabelPainterCache = {};
  final List<MovingVehicle> _vehicles = [];
  final List<WalkingPerson> _people = [];
  final List<DailyArrival> _dailyArrivals = [];
  final List<ParkingSlot> _parkingSlots = [
    ParkingSlot(spotTileNumber: 2092, approachTileNumber: 2063),
    ParkingSlot(spotTileNumber: 2121, approachTileNumber: 2093),
  ];
  static const int startingMoney = 20000;
  static const Map<String, int> buildCosts = {
    '라면': 500,
    '돈까스': 800,
    '국밥': 650,
    '비빔밥': 600,
    '김치찌개': 700,
    '제육볶음': 900,
    '불고기': 900,
    '설렁탕': 800,
    '백반': 1000,
    '주차': 200,
  };
  static const Map<String, RestaurantSpec> restaurantSpecs = {
    '라면': RestaurantSpec(
      cost: 500,
      sedanRange: VehicleDemandRange(min: 1.0, max: 2.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 1.0),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    '돈까스': RestaurantSpec(
      cost: 800,
      sedanRange: VehicleDemandRange(min: 1.0, max: 4.0),
      truckRange: VehicleDemandRange(min: 1.0, max: 1.6),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    '국밥': RestaurantSpec(
      cost: 650,
      sedanRange: VehicleDemandRange(min: 1.0, max: 2.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 1.0),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    '비빔밥': RestaurantSpec(
      cost: 600,
      sedanRange: VehicleDemandRange(min: 1.0, max: 2.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 1.0),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    '김치찌개': RestaurantSpec(
      cost: 700,
      sedanRange: VehicleDemandRange(min: 0.0, max: 4.0),
      truckRange: VehicleDemandRange(min: 1.0, max: 2.0),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '제육볶음': RestaurantSpec(
      cost: 900,
      sedanRange: VehicleDemandRange(min: 1.4, max: 2.4),
      truckRange: VehicleDemandRange(min: 1.0, max: 3.0),
      busRange: VehicleDemandRange(min: 0.0, max: 0.2),
    ),
    '불고기': RestaurantSpec(
      cost: 900,
      sedanRange: VehicleDemandRange(min: 0.0, max: 4.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 1.4),
      busRange: VehicleDemandRange(min: 0.04, max: 0.08),
    ),
    '설렁탕': RestaurantSpec(
      cost: 800,
      sedanRange: VehicleDemandRange(min: 0.4, max: 1.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 4.0),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '백반': RestaurantSpec(
      cost: 1000,
      sedanRange: VehicleDemandRange(min: 0.4, max: 2.0),
      truckRange: VehicleDemandRange(min: 2.0, max: 4.0),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
  };
  final ValueNotifier<String> timeLabel = ValueNotifier<String>(
    _formatGameTime(startingGameMinutes),
  );
  final ValueNotifier<String> moneyLabel = ValueNotifier<String>(
    _formatMoney(startingMoney),
  );
  final math.Random _random = math.Random();

  Offset _cameraCenter = Offset.zero;
  Rect _worldBounds = Rect.zero;
  double _zoom = 1.0;
  String? _pendingPlacementName;
  double _elapsedGameMinutes = startingGameMinutes.toDouble();
  double _previousElapsedGameMinutes = startingGameMinutes.toDouble();
  int _currentTrafficDay = -1;
  int _money = startingMoney;
  int _nextVehicleId = 1;
  int _nextPersonId = 1;

  @override
  Color backgroundColor() => const Color(0xFF698553);

  @override
  FutureOr<void> onLoad() {
    _buildTileMap();
    _rebuildTrafficPlan(force: true);
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
    _drawPeople(canvas);
    canvas.restore();
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

    final buildCost = buildCosts[_pendingPlacementName!];
    if (buildCost != null && _money < buildCost) {
      return;
    }

    for (var i = 0; i < footprint.length; i++) {
      final tileNumber = footprint[i];
      _placedTiles[tileNumber] = PlacedTileData(
        label: _pendingPlacementName!,
        backgroundColor: const Color(0xFF111111),
        showLabel: i == 0,
      );
    }
    if (buildCost != null) {
      _money -= buildCost;
      moneyLabel.value = _formatMoney(_money);
    }
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

    final targetZone = _placementZoneFor(_pendingPlacementName!);
    MapTile? best;
    var bestDistance = double.infinity;
    for (final tile in _tiles) {
      if (tile.zone != targetZone) {
        continue;
      }
      if (_placementFootprintFor(tile, _pendingPlacementName!) == null) {
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

  List<int>? _placementFootprintFor(MapTile anchorTile, String itemName) {
    if (_specialLabelFor(anchorTile) != null ||
        _placedTiles.containsKey(anchorTile.tileNumber)) {
      return null;
    }

    if (_isParkingFacility(itemName)) {
      if (anchorTile.zone != TileZone.parking) {
        return null;
      }
      return [anchorTile.tileNumber];
    }

    if (!_isRestaurant(itemName)) {
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
          _specialLabelFor(tile) != null ||
          _placedTiles.containsKey(tile.tileNumber)) {
        return null;
      }
      footprint.add(tile.tileNumber);
    }
    return footprint;
  }

  bool _isRestaurant(String itemName) => restaurantSpecs.containsKey(itemName);

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
    for (final tile in _tiles) {
      if (tile.logicalX == logicalX && tile.logicalY == logicalY) {
        return tile;
      }
    }
    return null;
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
    switch (type) {
      case VehicleType.sedan:
        return VehicleDemandRange(
          min: 12 + modifier.min,
          max: 15 + modifier.max,
        );
      case VehicleType.truck:
        return VehicleDemandRange(
          min: 1.5 + modifier.min,
          max: 4.5 + modifier.max,
        );
      case VehicleType.bus:
        return VehicleDemandRange(
          min: modifier.min,
          max: 0.75 + modifier.max,
        );
    }
  }

  VehicleDemandRange _buildingModifierFor(VehicleType type) {
    var minModifier = 0.0;
    var maxModifier = 0.0;
    for (final placed in _placedTiles.values) {
      if (!placed.showLabel) {
        continue;
      }
      final spec = restaurantSpecs[placed.label];
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
          vehicle.parkUntilMinute = _elapsedGameMinutes + 120;
          vehicle.parkingSlot!.occupiedBy = vehicle;
          vehicle.parkingSlot!.reservedBy = null;
          _spawnPeopleForVehicle(vehicle);
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

    final destination = _pickWalkingDestinationTile(slot.spotTileNumber);
    if (destination == null) {
      return;
    }

    final pathToDestination = _findPedestrianRouteToCommercial(
      startTileNumber: slot.spotTileNumber,
      targetTileNumber: destination,
    );
    if (pathToDestination == null || pathToDestination.length < 2) {
      return;
    }

    final peopleCount = _passengerCountFor(vehicle.type);
    final availableTypes = _availablePersonTypes(vehicle.type);
    for (var i = 0; i < peopleCount; i++) {
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
          visitMinutes: 20 + _random.nextInt(61),
          dwellUntilMinute: 0,
          speed: 34 + (_random.nextDouble() * 10),
        ),
      );
    }
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
      final neighbor = _tiles.cast<MapTile?>().firstWhere(
            (tile) =>
                tile?.logicalX == candidate.$1 &&
                tile?.logicalY == candidate.$2,
            orElse: () => null,
          );
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

  static String _formatClockOnly(double totalMinutes) {
    final snappedMinutes = totalMinutes.floor();
    final minutesIntoDay = snappedMinutes % gameMinutesPerDay;
    final hour = minutesIntoDay ~/ 60;
    final minute = minutesIntoDay % 60;
    return '$hour시 ${minute.toString().padLeft(2, '0')}분';
  }

  static String _formatMoney(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final indexFromEnd = digits.length - i;
      buffer.write(digits[i]);
      if (indexFromEnd > 1 && indexFromEnd % 3 == 1) {
        buffer.write(',');
      }
    }
    return '매출 ${buffer.toString()}원';
  }
}

class PlacedTileData {
  const PlacedTileData({
    required this.label,
    required this.backgroundColor,
    required this.showLabel,
  });

  final String label;
  final Color backgroundColor;
  final bool showLabel;
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

class RestaurantSpec {
  const RestaurantSpec({
    required this.cost,
    required this.sedanRange,
    required this.truckRange,
    required this.busRange,
  });

  final int cost;
  final VehicleDemandRange sedanRange;
  final VehicleDemandRange truckRange;
  final VehicleDemandRange busRange;
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
