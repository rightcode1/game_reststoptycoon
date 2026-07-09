import 'package:flutter_test/flutter_test.dart';

import 'package:reststop_tycoon/app.dart';
import 'package:reststop_tycoon/core/balance.dart';

void main() {
  group('밸런스 데이터 정합성', () {
    test('모든 식당 스펙은 양수 건설비·판매가와 유효한 수요 범위를 가진다', () {
      expect(Balance.storeSpecs, isNotEmpty);
      Balance.storeSpecs.forEach((name, spec) {
        expect(spec.cost, greaterThan(0), reason: '$name 건설비');
        expect(spec.salePrice, greaterThan(0), reason: '$name 판매가');
        for (final range in [spec.sedanRange, spec.truckRange, spec.busRange]) {
          expect(range.min, greaterThanOrEqualTo(0), reason: '$name 수요 최소');
          expect(
            range.max,
            greaterThanOrEqualTo(range.min),
            reason: '$name 수요 범위 역전',
          );
        }
      });
    });

    test('건설 화면의 매장 메뉴(식당·카페/디저트)는 전부 매장 스펙과 연결된다', () {
      final storeItems = [
        ...?ConstructionScreen.itemsByCategory['식당'],
        ...?ConstructionScreen.itemsByCategory['카페/디저트'],
      ];
      expect(storeItems, isNotEmpty);
      for (final item in storeItems) {
        expect(
          Balance.storeSpecs.containsKey(item),
          isTrue,
          reason: '건설 화면의 "$item"에 대응하는 StoreSpec이 없습니다',
        );
      }
    });

    test('매장 스펙에만 있고 건설 화면에 없는 유령 매장이 없다', () {
      final storeItems = [
        ...?ConstructionScreen.itemsByCategory['식당'],
        ...?ConstructionScreen.itemsByCategory['카페/디저트'],
      ];
      for (final name in Balance.storeSpecs.keys) {
        expect(
          storeItems.contains(name),
          isTrue,
          reason: '"$name" 스펙이 건설 화면 메뉴에 없습니다',
        );
      }
    });

    test('buildCostOf는 식당 스펙의 cost와 일치하고 주차 비용도 반환한다', () {
      for (final entry in Balance.storeSpecs.entries) {
        expect(Balance.buildCostOf(entry.key), entry.value.cost);
      }
      expect(Balance.buildCostOf('주차'), greaterThan(0));
      expect(Balance.buildCostOf('존재하지 않는 매장'), isNull);
    });

    test('salePriceOf는 식당에만 판매가를 반환한다', () {
      expect(Balance.salePriceOf('라면'), Balance.storeSpecs['라면']!.salePrice);
      expect(Balance.salePriceOf('주차'), isNull);
      expect(Balance.salePriceOf('존재하지 않는 매장'), isNull);
    });

    test('시간 밸런스 수치가 유효한 범위다', () {
      expect(Balance.startingMoney, greaterThan(0));
      expect(Balance.parkDurationMinutes, greaterThan(0));
      expect(Balance.queueGiveUpMinutes, greaterThan(0));
      expect(Balance.visitMinutesMin, greaterThan(0));
      expect(
        Balance.visitMinutesMax,
        greaterThanOrEqualTo(Balance.visitMinutesMin),
      );
      // 방문 체류 시간은 주차 시간 안에 끝나야 매출 흐름이 자연스럽다.
      expect(
        Balance.visitMinutesMax,
        lessThanOrEqualTo(Balance.parkDurationMinutes),
      );
    });

    test('평판·수요 밸런스 수치가 유효하다', () {
      expect(Balance.reputationStart, inInclusiveRange(0, 100));
      // 이탈이 정상 서비스보다 평판을 더 크게 움직여야 정체가 아프게 느껴진다.
      expect(
        Balance.reputationLostStep,
        greaterThan(Balance.reputationServedStep),
      );
      expect(Balance.reputationServedStep, greaterThan(0));
      expect(Balance.demandFactorMin, greaterThan(0));
      expect(
        Balance.demandFactorMax,
        greaterThan(Balance.demandFactorMin),
      );
    });

    test('demandFactor는 평판에 비례하며 바닥/천장을 지킨다', () {
      expect(Balance.demandFactor(0), closeTo(Balance.demandFactorMin, 1e-9));
      expect(Balance.demandFactor(100), closeTo(Balance.demandFactorMax, 1e-9));
      // 중간값은 선형 보간.
      expect(
        Balance.demandFactor(50),
        closeTo((Balance.demandFactorMin + Balance.demandFactorMax) / 2, 1e-9),
      );
      // 범위를 벗어난 입력도 클램프된다.
      expect(Balance.demandFactor(-20), closeTo(Balance.demandFactorMin, 1e-9));
      expect(Balance.demandFactor(200), closeTo(Balance.demandFactorMax, 1e-9));
    });
  });
}
