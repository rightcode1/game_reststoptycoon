# 휴게소 타이쿤 (Reststop Tycoon)

한국 고속도로 휴게소 경영 타이쿤. Flutter + Flame 기반 세로 전용 모바일 게임.

매장을 지으면 차량 유입이 늘고, 방문객이 매장에서 구매하며 자금이 쌓입니다.
업그레이드·직원 고용·주차 확장으로 휴게소를 키우고, 퀘스트를 따라 진행합니다.
저장/복원과 오프라인 수익 정산을 지원합니다.

## 실행

Flutter는 FVM으로 3.32.6에 고정되어 있습니다 (`flutter` 대신 항상 `fvm flutter`).

```bash
fvm install 3.32.6            # 최초 1회
fvm flutter pub get
cd ios && LANG=en_US.UTF-8 pod install && cd ..   # 새 클론/워크트리마다
fvm flutter run -d <시뮬레이터UDID>
```

## 테스트

```bash
fvm flutter analyze                                  # 정적 분석 (경고 0 유지)
fvm flutter test                                     # 유닛 테스트 (기기 불필요)
fvm flutter test integration_test/smoke_test.dart -d <UDID>   # 시뮬레이터 E2E
```

개발 규칙·아키텍처는 [CLAUDE.md](CLAUDE.md), 진행 현황·백로그는 [PROGRESS.md](PROGRESS.md) 참조.

## 에셋 교체 가이드

모든 그래픽·사운드는 현재 **플레이스홀더**입니다. 경로 상수는
[lib/core/assets.dart](lib/core/assets.dart) 한 곳에 모여 있습니다.

| 에셋 | 현재 상태 | 교체 방법 |
|------|-----------|-----------|
| 앱 아이콘 | 프로그래매틱 생성(아이소메트릭 타일) | 1024×1024 PNG로 `scripts/app_icon_placeholder_1024.png` 교체 후, `scripts/generate_placeholder_icon.py` 헤더의 sips 배포 절차 실행 (iOS appiconset + Android mipmap) |
| 사운드 SFX 8종 | 무음 (`SilentSoundPlayer`) | 파일을 `assets/sounds/`에 추가(파일명은 assets.dart 참조), pubspec에 디렉터리 등록, 오디오 패키지 기반 `SoundPlayer` 구현체를 만들어 `HighwayTycoonGame(soundPlayer: ...)`에 주입 |
| 차량 스프라이트 | 색상 사각형 렌더링 | `assets/images/vehicles/`에 스프라이트 있음(미사용). `_drawVehicles()`를 스프라이트 렌더링으로 교체 |
| 보행자 스프라이트 | 도형(원/삼각형/사각형/별) | `_drawPeople()` 교체. `PersonType`별 8종 필요 |
| 타일/시설 그래픽 | 색상 마름모 + 텍스트 라벨 | `_drawTileMap()`의 타일 채색을 스프라이트로 교체. 마름모 타일 반폭 42 / 반높이 22 기준 |

## 릴리즈 체크리스트

- [x] 앱 표시명: iOS/Android '휴게소 타이쿤' (2026-07-09)
- [x] 세로(portrait) 고정: iOS Info.plist + Android manifest (2026-07-09)
- [x] 버전: pubspec `0.2.0+2`
- [ ] **번들 ID 변경 필요**: 현재 `com.rightcode.fen52`(다른 프로젝트 잔재).
      iOS `PRODUCT_BUNDLE_IDENTIFIER`(Xcode)와 Android `applicationId`(build.gradle)를
      정식 ID로 교체하고 서명/프로비저닝 구성 — **스토어 계정 결정 사항**
- [x] 릴리즈 빌드 검증: `flutter build ios --release --no-codesign`(56.6MB),
      `flutter build apk --release`(48.9MB) 통과 (2026-07-09)
- [ ] Android 릴리즈 서명 키(keystore) 구성 — 현재 debug 서명
- [ ] 에셋 교체 (위 가이드 참조) 후 스토어 스크린샷 제작
