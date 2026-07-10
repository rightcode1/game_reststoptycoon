import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/balance.dart';
import 'game/highway_tycoon_game.dart';

class RestStopTycoonApp extends StatefulWidget {
  const RestStopTycoonApp({super.key});

  @override
  State<RestStopTycoonApp> createState() => _RestStopTycoonAppState();
}

class _RestStopTycoonAppState extends State<RestStopTycoonApp>
    with WidgetsBindingObserver {
  late final HighwayTycoonGame _game;
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  double _lastGestureScale = 1.0;

  @override
  void initState() {
    super.initState();
    _game = HighwayTycoonGame();
    _game.notice.addListener(_onNotice);
    _game.upgradeRequest.addListener(_onUpgradeRequest);
    _game.landUnlockRequest.addListener(_onLandUnlockRequest);
    _game.treeClearRequest.addListener(_onTreeClearRequest);
    _game.offlineEarnings.addListener(_onOfflineEarnings);
    _game.tutorialRequested.addListener(_onTutorialRequested);
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _game.notice.removeListener(_onNotice);
    _game.upgradeRequest.removeListener(_onUpgradeRequest);
    _game.landUnlockRequest.removeListener(_onLandUnlockRequest);
    _game.treeClearRequest.removeListener(_onTreeClearRequest);
    _game.offlineEarnings.removeListener(_onOfflineEarnings);
    _game.tutorialRequested.removeListener(_onTutorialRequested);
    _game.timeLabel.dispose();
    _game.moneyLabel.dispose();
    _game.notice.dispose();
    _game.pendingPlacementLabel.dispose();
    _game.upgradeRequest.dispose();
    _game.landUnlockRequest.dispose();
    _game.treeClearRequest.dispose();
    _game.offlineEarnings.dispose();
    _game.questLabel.dispose();
    _game.reputation.dispose();
    _game.congestion.dispose();
    _game.tutorialRequested.dispose();
    _game.soundEnabled.dispose();
    super.dispose();
  }

  void _onTutorialRequested() {
    if (!_game.tutorialRequested.value) {
      return;
    }
    _game.tutorialRequested.value = false;
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }

    const pages = [
      (
        '휴게소 타이쿤에 오신 것을 환영합니다!',
        '고속도로를 달리던 차들이 휴게소에 들릅니다.\n'
            '방문객에게 먹거리를 팔아 휴게소를 키워보세요.',
      ),
      (
        '건설하기',
        '하단 [건설] 버튼에서 매장을 고른 뒤,\n'
            '맵의 회색 하이라이트 타일을 탭하면 배치됩니다.\n'
            '매장이 많을수록 더 많은 차가 들어옵니다.',
      ),
      (
        '키우기',
        '배치된 매장을 탭하면 업그레이드와 직원 고용이 가능합니다.\n'
            '좌상단의 목표를 따라가면 보상을 받을 수 있어요!',
      ),
    ];
    var pageIndex = 0;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final (title, body) = pages[pageIndex];
            final isLast = pageIndex == pages.length - 1;
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2218),
              title: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: Text(
                body,
                style: const TextStyle(
                  color: Color(0xFFE7D7B7),
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    if (isLast) {
                      Navigator.of(dialogContext).pop();
                      _game.completeTutorial();
                      return;
                    }
                    setState(() {
                      pageIndex++;
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD49C3D),
                    foregroundColor: const Color(0xFF23170A),
                  ),
                  child: Text(
                    isLast ? '시작하기' : '다음',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _onOfflineEarnings() {
    final report = _game.offlineEarnings.value;
    if (report == null) {
      return;
    }
    _game.offlineEarnings.value = null;
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2218),
          title: const Text(
            '부재 중 수익',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            '자리를 비운 ${report.offlineGameDays.round()}게임일 동안 '
            '매장들이 ${report.amount}원을 벌었습니다!',
            style: const TextStyle(
              color: Color(0xFFE7D7B7),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD49C3D),
                foregroundColor: const Color(0xFF23170A),
              ),
              child: const Text(
                '확인',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
  }

  void _onLandUnlockRequest() {
    final request = _game.landUnlockRequest.value;
    if (request == null) {
      return;
    }
    _game.landUnlockRequest.value = null;
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2A2218),
        title: const Text(
          '부지 해금',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '이 부지를 ${request.cost}원에 해금할까요?',
          style: const TextStyle(
            color: Color(0xFFE7D7B7),
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              _game.unlockPlot(request.plotKey);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('해금'),
          ),
        ],
      ),
    );
  }

  void _onTreeClearRequest() {
    final request = _game.treeClearRequest.value;
    if (request == null) {
      return;
    }
    _game.treeClearRequest.value = null;
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2A2218),
        title: const Text(
          '나무 치우기',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '이 나무를 ${request.cost}원에 치울까요?',
          style: const TextStyle(
            color: Color(0xFFE7D7B7),
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              _game.clearTree(request.tileNumber);
              Navigator.of(dialogContext).pop();
            },
            child: const Text('치우기'),
          ),
        ],
      ),
    );
  }

  void _onUpgradeRequest() {
    final request = _game.upgradeRequest.value;
    if (request == null) {
      return;
    }
    _game.upgradeRequest.value = null;
    final context = _navigatorKey.currentContext;
    if (context == null) {
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        const bodyStyle = TextStyle(
          color: Color(0xFFE7D7B7),
          fontWeight: FontWeight.w600,
        );
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2218),
          title: Text(
            '${request.storeName} Lv.${request.level}',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                request.nextSalePrice == null
                    ? '판매가: ${request.currentSalePrice}원'
                    : '판매가: ${request.currentSalePrice}원 → '
                        '${request.nextSalePrice}원',
                style: bodyStyle,
              ),
              const SizedBox(height: 8),
              Text(
                request.upgradeCost == null
                    ? '이미 최대 레벨입니다'
                    : '업그레이드 비용: ${request.upgradeCost}원',
                style: bodyStyle,
              ),
              const SizedBox(height: 8),
              Text(
                '직원: ${request.staffCount}/${Balance.maxStaffPerStore}명 '
                '(1명당 판매 수익 +${(Balance.staffSalesBonusPerStaff * 100).round()}%)',
                style: bodyStyle,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('닫기'),
            ),
            if (request.staffHireCost != null)
              FilledButton.tonal(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _game.hireStaff(request.anchorTileNumber);
                },
                child: Text(
                  '직원 고용 (${request.staffHireCost}원)',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            if (request.upgradeCost != null)
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _game.upgradeStore(request.anchorTileNumber);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD49C3D),
                  foregroundColor: const Color(0xFF23170A),
                ),
                child: const Text(
                  '업그레이드',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        );
      },
    );
  }

  void _onNotice() {
    final message = _game.notice.value;
    if (message == null) {
      return;
    }
    _game.notice.value = null;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드 전환/종료 직전에 진행 상태를 저장한다.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _game.saveNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C7680),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _RestStopHome(
        game: _game,
        onScaleStart: () {
          _lastGestureScale = 1.0;
        },
        onScaleUpdate: (details) {
          _game.panBy(details.focalPointDelta);

          final scaleDelta = details.scale / _lastGestureScale;
          _lastGestureScale = details.scale;
          _game.zoomAt(
            scaleDelta: scaleDelta,
            focalPoint: details.localFocalPoint,
          );
        },
      ),
    );
  }
}

class _RestStopHome extends StatelessWidget {
  const _RestStopHome({
    required this.game,
    required this.onScaleStart,
    required this.onScaleUpdate,
  });

  final HighwayTycoonGame game;
  final VoidCallback onScaleStart;
  final ValueChanged<ScaleUpdateDetails> onScaleUpdate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF7E9A61),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) => onScaleStart(),
              onScaleUpdate: onScaleUpdate,
              onTapUp: (details) => game.handleTap(details.localPosition),
              child: GameWidget<HighwayTycoonGame>(game: game),
            ),
          ),
          IgnorePointer(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ValueListenableBuilder<String>(
                        valueListenable: game.timeLabel,
                        builder: (context, value, _) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC1E1A16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0x66F0D69A),
                              ),
                            ),
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<String?>(
                        valueListenable: game.questLabel,
                        builder: (context, value, _) {
                          if (value == null) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC2E4A2C),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0x669CD98B),
                              ),
                            ),
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      ValueListenableBuilder<double>(
                        valueListenable: game.reputation,
                        builder: (context, value, _) {
                          final rep = value.round();
                          // 평판이 낮을수록 붉게, 높을수록 초록으로.
                          final color = Color.lerp(
                            const Color(0xFFE57373),
                            const Color(0xFF9CD98B),
                            (value / 100).clamp(0.0, 1.0),
                          )!;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC1E1A16),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: color),
                            ),
                            child: Text(
                              '평판 $rep',
                              style: TextStyle(
                                color: color,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          );
                        },
                      ),
                      ValueListenableBuilder<int>(
                        valueListenable: game.congestion,
                        builder: (context, value, _) {
                          if (value <= 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xCC4A2C2C),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0x66E57373),
                                ),
                              ),
                              child: Text(
                                '정체 · 오늘 놓친 손님 $value대',
                                style: const TextStyle(
                                  color: Color(0xFFFFCDD2),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Align(
                alignment: Alignment.topRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showArrivalScheduleDialog(context, game),
                      child: ValueListenableBuilder<String>(
                        valueListenable: game.moneyLabel,
                        builder: (context, value, _) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC1E1A16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0x66F0D69A),
                              ),
                            ),
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showSettingsDialog(context, game),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xCC1E1A16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0x66F0D69A),
                          ),
                        ),
                        child: const Icon(
                          Icons.settings,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: ValueListenableBuilder<String?>(
          valueListenable: game.pendingPlacementLabel,
          builder: (context, placingItem, _) {
            if (placingItem != null) {
              return FilledButton(
                onPressed: game.cancelPlacement,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8C3B2E),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  '$placingItem 배치 취소',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            }
            return FilledButton(
              onPressed: () async {
                final selectedItem = await Navigator.of(context).push<String>(
                  MaterialPageRoute<String>(
                    builder: (_) => const ConstructionScreen(),
                  ),
                );
                if (selectedItem != null) {
                  game.startPlacement(selectedItem);
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD49C3D),
                foregroundColor: const Color(0xFF23170A),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                '건설',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, HighwayTycoonGame game) {
    const bodyStyle = TextStyle(
      color: Color(0xFFE7D7B7),
      fontWeight: FontWeight.w600,
    );
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2218),
          title: const Text(
            '설정',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('사운드', style: bodyStyle),
                  ValueListenableBuilder<bool>(
                    valueListenable: game.soundEnabled,
                    builder: (context, enabled, _) {
                      return Switch(
                        value: enabled,
                        activeTrackColor: const Color(0xFFD49C3D),
                        onChanged: game.setSoundEnabled,
                      );
                    },
                  ),
                ],
              ),
              const Text(
                '(사운드 에셋 준비 전 — 현재 무음)',
                style: TextStyle(
                  color: Color(0xFF9A8A6E),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  game.tutorialRequested.value = true;
                },
                child: const Text('튜토리얼 다시 보기'),
              ),
              TextButton(
                onPressed: () => _confirmReset(dialogContext, game),
                child: const Text(
                  '데이터 초기화',
                  style: TextStyle(color: Color(0xFFE57373)),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD49C3D),
                foregroundColor: const Color(0xFF23170A),
              ),
              child: const Text(
                '닫기',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
  }

  void _confirmReset(BuildContext settingsContext, HighwayTycoonGame game) {
    showDialog<void>(
      context: settingsContext,
      builder: (confirmContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2218),
          title: const Text(
            '정말 초기화할까요?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: const Text(
            '자금, 시설, 퀘스트 등 모든 진행 상황이 삭제됩니다.\n'
            '이 작업은 되돌릴 수 없습니다.',
            style: TextStyle(
              color: Color(0xFFE7D7B7),
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(confirmContext).pop(); // 확인 다이얼로그 닫기
                Navigator.of(settingsContext).pop(); // 설정 다이얼로그 닫기
                game.resetGame();
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB23B2E),
                foregroundColor: Colors.white,
              ),
              child: const Text(
                '초기화',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showArrivalScheduleDialog(
    BuildContext context,
    HighwayTycoonGame game,
  ) {
    final schedule = game.todayArrivalSchedule;
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2A2218),
          title: const Text(
            '오늘 유입 일정',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: schedule.isEmpty
                ? const Text(
                    '오늘 남은 유입 일정이 없습니다.',
                    style: TextStyle(
                      color: Color(0xFFE7D7B7),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: schedule
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                item,
                                style: const TextStyle(
                                  color: Color(0xFFE7D7B7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }
}

class ConstructionScreen extends StatefulWidget {
  const ConstructionScreen({super.key});

  /// 건설 화면에 노출되는 매장 카탈로그.
  /// 매장 이름 문자열이 곧 게임 로직(`Balance.storeSpecs` 등)의 키이므로
  /// 항목을 추가/변경할 때 `lib/core/balance.dart`도 함께 맞춰야 한다.
  /// (`test/balance_test.dart`가 정합성을 검증)
  static const Map<String, List<String>> itemsByCategory = {
    '식당': [
      '라면',
      '돈까스',
      '국밥',
      '비빔밥',
      '김치찌개',
      '제육볶음',
      '불고기',
      '설렁탕',
      '백반',
    ],
    '카페/디저트': [
      '핫도그',
      '떡볶이',
      '닭강정',
      '호두과자',
      '감자/옥수수',
      '카페',
      '빵집',
      '건어물',
    ],
    '편의시설': [],
    '특수시설': ['주차'],
  };

  @override
  State<ConstructionScreen> createState() => _ConstructionScreenState();
}

class _ConstructionScreenState extends State<ConstructionScreen> {
  static const List<String> _categories = [
    '식당',
    '카페/디저트',
    '편의시설',
    '특수시설',
  ];

  static const Map<String, String> _descriptions = {
    '라면': '빠르게 조리해 회전율을 높일 수 있는 대표 휴게소 식당 예시입니다.',
    '돈까스': '가족 단위 방문객도 무난하게 선택할 수 있는 인기 메뉴 예시입니다.',
    '국밥': '장거리 운전자에게 든든한 한 끼를 제공하는 한식 매장 예시입니다.',
    '비빔밥': '조리와 제공이 비교적 단순한 한식형 매장 예시입니다.',
    '김치찌개': '국물 메뉴 수요를 노린 뜨끈한 식당 구성 예시입니다.',
    '제육볶음': '매콤한 정식 메뉴를 앞세운 식당 콘셉트 예시입니다.',
    '불고기': '남녀노소 폭넓게 선택할 수 있는 대표 한식 메뉴 예시입니다.',
    '설렁탕': '진한 국물 중심의 프리미엄 식당 콘셉트 예시입니다.',
    '백반': '기본 반찬 구성으로 운영하는 정식형 식당 예시입니다.',
    '핫도그': '이동 중 빠르게 먹을 수 있는 간식 부스형 매장 예시입니다.',
    '떡볶이': '분식 수요를 겨냥한 간편식 매장 예시입니다.',
    '닭강정': '포장 판매에도 적합한 간식형 매장 예시입니다.',
    '호두과자': '휴게소 대표 간식 이미지에 맞는 디저트 매장 예시입니다.',
    '감자/옥수수': '길거리 간식 판매형 코너 예시입니다.',
    '카페': '음료와 휴식 수요를 함께 잡는 기본 카페 매장 예시입니다.',
    '빵집': '간단한 식사 대체 수요까지 흡수하는 베이커리 예시입니다.',
    '건어물': '지역 특산 간식 판매 코너 예시입니다.',
    '주차': '추가 주차 공간을 운영하는 특수시설 예시입니다.',
  };

  String _selectedCategory = _categories.first;
  String? _previewItem;

  @override
  Widget build(BuildContext context) {
    final items =
        ConstructionScreen.itemsByCategory[_selectedCategory] ??
            const <String>[];
    final previewDescription = _previewItem == null
        ? null
        : _descriptions[_previewItem] ?? '매장 설명 예시입니다.';

    return Scaffold(
      backgroundColor: const Color(0xFFF3E7CE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFC8924D),
        foregroundColor: const Color(0xFF25180C),
        title: const Text(
          '건설',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 74,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final selected = category == _selectedCategory;
                  return ChoiceChip(
                    label: Text(category),
                    selected: selected,
                    onSelected: (_) {
                      setState(() {
                        _selectedCategory = category;
                        _previewItem = null;
                      });
                    },
                    selectedColor: const Color(0xFF2D2A26),
                    backgroundColor: const Color(0xFFE4CC9B),
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : const Color(0xFF2A2117),
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  );
                },
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemCount: _categories.length,
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        '준비 중',
                        style: TextStyle(
                          color: Color(0xFF6B573D),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _ConstructionItemTile(
                          label: item,
                          selected: _previewItem == item,
                          onTap: () {
                            if (_previewItem == item) {
                              Navigator.of(context).pop(item);
                              return;
                            }
                            setState(() {
                              _previewItem = item;
                            });
                          },
                        );
                      },
                    ),
            ),
            if (previewDescription != null)
              _ConstructionDescriptionSheet(
                title: _previewItem!,
                description: previewDescription,
                onClose: () {
                  setState(() {
                    _previewItem = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ConstructionItemTile extends StatelessWidget {
  const _ConstructionItemTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2D2A26) : const Color(0xFFFFF5E1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFFF2D181) : const Color(0xFFC99A5F),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF2A2117),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ConstructionDescriptionSheet extends StatelessWidget {
  const _ConstructionDescriptionSheet({
    required this.title,
    required this.description,
    required this.onClose,
  });

  final String title;
  final String description;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: Color(0xFF2A2218),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFFE7D7B7),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '같은 박스를 한 번 더 누르면 맵으로 돌아가 중앙 회색 타일에 배치할 수 있습니다.',
            style: TextStyle(
              color: Color(0xFFD3BF98),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
