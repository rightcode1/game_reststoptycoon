/// 게임 밸런스 수치 모음.
///
/// 가격·수요·시간 등 튜닝 대상 수치는 게임 로직에 하드코딩하지 않고
/// 이 파일에서만 관리한다. (`test/balance_test.dart`가 정합성을 검증)
library;

/// 차량 유형별 일일 수요 범위(대/일). 실제 대수는 이 범위에서 무작위 추출.
class VehicleDemandRange {
  const VehicleDemandRange({
    required this.min,
    required this.max,
  });

  final double min;
  final double max;
}

/// 매장(식당·카페/디저트) 한 곳의 밸런스 스펙:
/// 건설비, 1인 판매가, 차량 유형별 수요 보정치.
class StoreSpec {
  const StoreSpec({
    required this.cost,
    required this.salePrice,
    required this.sedanRange,
    required this.truckRange,
    required this.busRange,
  });

  final int cost;
  final int salePrice;
  final VehicleDemandRange sedanRange;
  final VehicleDemandRange truckRange;
  final VehicleDemandRange busRange;
}

abstract final class Balance {
  /// 시작 자금(원).
  static const int startingMoney = 20000;

  /// 차량이 주차 슬롯을 점유하는 시간(게임 분).
  static const int parkDurationMinutes = 120;

  /// 대기열에서 버티다 포기하고 통과 차량으로 전환되는 시간(게임 분).
  static const int queueGiveUpMinutes = 60;

  /// 방문객이 매장 앞에서 체류하는 시간 범위(게임 분).
  static const int visitMinutesMin = 20;
  static const int visitMinutesMax = 80;

  /// 차량 유형별 일일 기본 수요(배치된 매장 보정치 제외).
  static const VehicleDemandRange sedanDailyBase =
      VehicleDemandRange(min: 12, max: 15);
  static const VehicleDemandRange truckDailyBase =
      VehicleDemandRange(min: 1.5, max: 4.5);
  static const VehicleDemandRange busDailyBase =
      VehicleDemandRange(min: 0, max: 0.75);

  /// 식당 외 시설 건설비(원).
  static const Map<String, int> facilityCosts = {
    '주차': 200,
  };

  /// 매장 스펙(식당 + 카페/디저트). 키는 건설 화면
  /// (`ConstructionScreen.itemsByCategory`)의 매장 이름 문자열과
  /// 반드시 일치해야 한다.
  static const Map<String, StoreSpec> storeSpecs = {
    '라면': StoreSpec(
      cost: 500,
      salePrice: 45,
      sedanRange: VehicleDemandRange(min: 1.0, max: 2.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 1.0),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    '돈까스': StoreSpec(
      cost: 800,
      salePrice: 65,
      sedanRange: VehicleDemandRange(min: 1.0, max: 4.0),
      truckRange: VehicleDemandRange(min: 1.0, max: 1.6),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    '국밥': StoreSpec(
      cost: 650,
      salePrice: 55,
      sedanRange: VehicleDemandRange(min: 1.0, max: 2.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 1.0),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    '비빔밥': StoreSpec(
      cost: 600,
      salePrice: 50,
      sedanRange: VehicleDemandRange(min: 1.0, max: 2.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 1.0),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    '김치찌개': StoreSpec(
      cost: 700,
      salePrice: 55,
      sedanRange: VehicleDemandRange(min: 0.0, max: 4.0),
      truckRange: VehicleDemandRange(min: 1.0, max: 2.0),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '제육볶음': StoreSpec(
      cost: 900,
      salePrice: 65,
      sedanRange: VehicleDemandRange(min: 1.4, max: 2.4),
      truckRange: VehicleDemandRange(min: 1.0, max: 3.0),
      busRange: VehicleDemandRange(min: 0.0, max: 0.2),
    ),
    '불고기': StoreSpec(
      cost: 900,
      salePrice: 70,
      sedanRange: VehicleDemandRange(min: 0.0, max: 4.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 1.4),
      busRange: VehicleDemandRange(min: 0.04, max: 0.08),
    ),
    '설렁탕': StoreSpec(
      cost: 800,
      salePrice: 65,
      sedanRange: VehicleDemandRange(min: 0.4, max: 1.0),
      truckRange: VehicleDemandRange(min: 0.4, max: 4.0),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '백반': StoreSpec(
      cost: 1000,
      salePrice: 60,
      sedanRange: VehicleDemandRange(min: 0.4, max: 2.0),
      truckRange: VehicleDemandRange(min: 2.0, max: 4.0),
      busRange: VehicleDemandRange(min: 0.1, max: 0.1),
    ),
    // ---- 카페/디저트: 식당보다 싸고 수요 보정치도 작다 ----
    '핫도그': StoreSpec(
      cost: 300,
      salePrice: 25,
      sedanRange: VehicleDemandRange(min: 0.4, max: 1.0),
      truckRange: VehicleDemandRange(min: 0.2, max: 0.6),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '떡볶이': StoreSpec(
      cost: 350,
      salePrice: 30,
      sedanRange: VehicleDemandRange(min: 0.5, max: 1.2),
      truckRange: VehicleDemandRange(min: 0.1, max: 0.4),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '닭강정': StoreSpec(
      cost: 450,
      salePrice: 40,
      sedanRange: VehicleDemandRange(min: 0.5, max: 1.4),
      truckRange: VehicleDemandRange(min: 0.2, max: 0.6),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '호두과자': StoreSpec(
      cost: 400,
      salePrice: 30,
      sedanRange: VehicleDemandRange(min: 0.6, max: 1.5),
      truckRange: VehicleDemandRange(min: 0.2, max: 0.5),
      busRange: VehicleDemandRange(min: 0.1, max: 0.2),
    ),
    '감자/옥수수': StoreSpec(
      cost: 250,
      salePrice: 20,
      sedanRange: VehicleDemandRange(min: 0.3, max: 0.8),
      truckRange: VehicleDemandRange(min: 0.2, max: 0.5),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '카페': StoreSpec(
      cost: 600,
      salePrice: 35,
      sedanRange: VehicleDemandRange(min: 0.8, max: 2.0),
      truckRange: VehicleDemandRange(min: 0.3, max: 0.8),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '빵집': StoreSpec(
      cost: 550,
      salePrice: 35,
      sedanRange: VehicleDemandRange(min: 0.6, max: 1.5),
      truckRange: VehicleDemandRange(min: 0.2, max: 0.6),
      busRange: VehicleDemandRange(min: 0.0, max: 0.1),
    ),
    '건어물': StoreSpec(
      cost: 400,
      salePrice: 30,
      sedanRange: VehicleDemandRange(min: 0.3, max: 1.0),
      truckRange: VehicleDemandRange(min: 0.3, max: 0.8),
      busRange: VehicleDemandRange(min: 0.1, max: 0.2),
    ),
  };

  /// 이름으로 건설비 조회. 비용이 정의되지 않은 항목은 null(무료 배치).
  static int? buildCostOf(String itemName) =>
      storeSpecs[itemName]?.cost ?? facilityCosts[itemName];

  /// 이름으로 1인 판매가 조회. 매장이 아니면 null(매출 없음).
  static int? salePriceOf(String itemName) =>
      storeSpecs[itemName]?.salePrice;

  /// 매장 최대 레벨.
  static const int storeMaxLevel = 5;

  /// 레벨 n → n+1 업그레이드 비용 = 건설비 × [upgradeCostFactor] × n.
  /// (2026-07-09 튜닝: 실측 매장당 판매 ~5.5건/게임일 기준, Lv2 회수 ≈2.4게임일)
  static const double upgradeCostFactor = 0.6;

  /// 레벨당 판매가 증가율. 판매가 = 기본가 × (1 + 증가율 × (레벨 - 1)).
  static const double salePriceIncreasePerLevel = 0.5;

  /// 다음 레벨 업그레이드 비용. 매장이 아니거나 이미 최대 레벨이면 null.
  static int? upgradeCostOf(String itemName, int currentLevel) {
    final spec = storeSpecs[itemName];
    if (spec == null || currentLevel < 1 || currentLevel >= storeMaxLevel) {
      return null;
    }
    return (spec.cost * upgradeCostFactor * currentLevel).round();
  }

  /// 오프라인 정산: 매장 1곳당 게임 1일에 발생한 것으로 치는 판매 건수.
  /// (2026-07-09 튜닝: 실측 온라인 판매 ~5.5건/게임일에 맞춤 —
  /// 방치가 실플레이보다 이득이 되지 않게)
  static const double offlineSalesPerStorePerDay = 5;

  /// 오프라인 정산으로 인정하는 최대 부재 시간(현실 시간).
  static const Duration offlineEarningsCap = Duration(hours: 8);

  /// 레벨을 반영한 1인 판매가. 매장이 아니면 null.
  static int? salePriceAt(String itemName, int level) {
    final spec = storeSpecs[itemName];
    if (spec == null) {
      return null;
    }
    return (spec.salePrice * (1 + salePriceIncreasePerLevel * (level - 1)))
        .round();
  }

  /// 방문객 매장 선택 시 모든 매장에 보장되는 최소 선호 가중치.
  /// (수요 범위 중간값이 0에 가까운 매장도 최소한의 손님은 받는다)
  static const double minStoreAffinity = 0.05;

  /// 매장당 최대 직원 수.
  static const int maxStaffPerStore = 3;

  /// n번째 직원 고용 비용 = 건설비 × [staffHireCostFactor] × n.
  /// (2026-07-09 튜닝: 1명째 회수 ≈3게임일 목표)
  static const double staffHireCostFactor = 0.4;

  /// 직원 1명당 판매 수익 보너스율.
  static const double staffSalesBonusPerStaff = 0.25;

  /// 다음 직원 고용 비용. 매장이 아니거나 이미 최대 인원이면 null.
  static int? staffHireCostOf(String itemName, int currentStaffCount) {
    final spec = storeSpecs[itemName];
    if (spec == null ||
        currentStaffCount < 0 ||
        currentStaffCount >= maxStaffPerStore) {
      return null;
    }
    return (spec.cost * staffHireCostFactor * (currentStaffCount + 1)).round();
  }

  /// 레벨·직원 보너스를 모두 반영한 1인 판매가. 매장이 아니면 null.
  static int? salePriceWith(String itemName, int level, int staffCount) {
    final base = salePriceAt(itemName, level);
    if (base == null) {
      return null;
    }
    return (base * (1 + staffSalesBonusPerStaff * staffCount)).round();
  }
}
