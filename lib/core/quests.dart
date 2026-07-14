/// 순차 진행 퀘스트(목표) 정의.
///
/// 게임은 [questLine]을 앞에서부터 하나씩 진행하며, 현재 퀘스트의
/// 지표([QuestMetric])가 목표치에 도달하면 보상을 지급하고 다음으로 넘어간다.
library;

/// 퀘스트가 추적하는 누적 지표.
enum QuestMetric {
  /// 건설한 매장(식당·카페/디저트) 수.
  storesBuilt,

  /// 방문객 판매 건수(오프라인 정산 제외).
  salesCount,

  /// 고용한 직원 수(전 매장 합계).
  staffHired,

  /// 매장 업그레이드 횟수.
  upgradesDone,

  /// 확장한 주차 슬롯 수.
  parkingBuilt,

  /// 해금한 부지 구역 수.
  landUnlocked,

  /// 치운 나무 수.
  treeCleared,
}

class QuestSpec {
  const QuestSpec({
    required this.description,
    required this.metric,
    required this.target,
    required this.reward,
  });

  final String description;
  final QuestMetric metric;
  final int target;

  /// 달성 보상(원).
  final int reward;
}

/// 순차 퀘스트 라인. 순서를 바꾸면 진행 중인 저장의 questIndex 의미가
/// 달라지므로 기존 항목 사이에 삽입하지 말고 끝에만 추가할 것.
const List<QuestSpec> questLine = [
  QuestSpec(
    description: '첫 매장을 건설하세요',
    metric: QuestMetric.storesBuilt,
    target: 1,
    reward: 400,
  ),
  QuestSpec(
    description: '방문객에게 5번 판매하세요',
    metric: QuestMetric.salesCount,
    target: 5,
    reward: 300,
  ),
  QuestSpec(
    description: '매장을 3곳으로 늘리세요',
    metric: QuestMetric.storesBuilt,
    target: 3,
    reward: 800,
  ),
  QuestSpec(
    description: '주차 공간을 1곳 확장하세요',
    metric: QuestMetric.parkingBuilt,
    target: 1,
    reward: 300,
  ),
  QuestSpec(
    description: '직원을 1명 고용하세요',
    metric: QuestMetric.staffHired,
    target: 1,
    reward: 500,
  ),
  QuestSpec(
    description: '매장을 1번 업그레이드하세요',
    metric: QuestMetric.upgradesDone,
    target: 1,
    reward: 800,
  ),
  QuestSpec(
    description: '누적 판매 50건을 달성하세요',
    metric: QuestMetric.salesCount,
    target: 50,
    reward: 1500,
  ),
  QuestSpec(
    description: '매장을 6곳으로 늘리세요',
    metric: QuestMetric.storesBuilt,
    target: 6,
    reward: 2000,
  ),
  QuestSpec(
    description: '직원을 총 5명 고용하세요',
    metric: QuestMetric.staffHired,
    target: 5,
    reward: 2000,
  ),
  QuestSpec(
    description: '누적 판매 120건을 달성하세요',
    metric: QuestMetric.salesCount,
    target: 120,
    reward: 5000,
  ),
  QuestSpec(
    description: '나무를 3그루 치우세요',
    metric: QuestMetric.treeCleared,
    target: 3,
    reward: 1000,
  ),
  QuestSpec(
    description: '부지를 3구역 해금하세요',
    metric: QuestMetric.landUnlocked,
    target: 3,
    reward: 3000,
  ),
];
