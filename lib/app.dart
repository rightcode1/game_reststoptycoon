import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/highway_tycoon_game.dart';

class RestStopTycoonApp extends StatefulWidget {
  const RestStopTycoonApp({super.key});

  @override
  State<RestStopTycoonApp> createState() => _RestStopTycoonAppState();
}

class _RestStopTycoonAppState extends State<RestStopTycoonApp> {
  late final HighwayTycoonGame _game;
  double _lastGestureScale = 1.0;

  @override
  void initState() {
    super.initState();
    _game = HighwayTycoonGame();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _game.timeLabel.dispose();
    _game.moneyLabel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
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
                  child: ValueListenableBuilder<String>(
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
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
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
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
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
        ),
      ),
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

  static const Map<String, List<String>> _itemsByCategory = {
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
    final items = _itemsByCategory[_selectedCategory] ?? const <String>[];
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
