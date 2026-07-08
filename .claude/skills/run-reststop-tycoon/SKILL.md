---
name: run-reststop-tycoon
description: Build, run, and drive the reststop_tycoon Flutter game on the iOS simulator. Use when asked to run/start the app, take a screenshot, hot-reload, or verify a change end-to-end (build → launch → tap → observe).
---

Flutter + Flame 게임을 iOS 시뮬레이터에서 빌드/실행/조작하는 방법.
프로그래매틱 조작(탭, 상태 검증)은 `integration_test/smoke_test.dart`가 드라이버다 —
`simctl`에는 tap 명령이 없어서 실행 중인 앱을 셸에서 직접 탭할 수 없다.

모든 경로는 리포 루트 기준. 모든 명령은 `fvm flutter`를 사용한다 — 이 머신에는 `flutter`가 PATH에 없다.

## Prerequisites

macOS 전용 (Xcode + iOS 시뮬레이터 필요). 이미 설치되어 있어야 하는 것: Xcode, `fvm`(brew), CocoaPods.

Flutter SDK는 `.fvmrc`로 3.32.6에 고정되어 있고, **FVM 캐시에 없으면 `fvm flutter` 첫 실행이
인터랙티브 설치 프롬프트에서 멈춘다**. 반드시 먼저 비대화식으로 설치할 것:

```bash
fvm install 3.32.6
```

## Setup

```bash
fvm flutter pub get
cd ios && LANG=en_US.UTF-8 pod install && cd ..
```

`pod install`은 새 클론/새 git worktree마다 필요하다 (`ios/Pods`는 gitignore됨).
빼먹으면 Xcode 빌드가 `Unable to load contents of file list: ... Pods-Runner-*.xcfilelist`로 실패한다.
`LANG` 미지정 시 CocoaPods가 UTF-8 경고를 낸다. 설치 후 나오는
"did not set the base configuration ... profile.xcconfig" 경고는 무시해도 된다 (debug 빌드 정상).

## 시뮬레이터 준비

```bash
# 사용 가능한 iPhone 시뮬레이터 UDID 조회 (머신마다 다름)
xcrun simctl list devices available | grep iPhone
# 부팅 + 창 표시 + 준비 대기
UDID=<위에서 고른 UDID>
xcrun simctl boot "$UDID"; open -a Simulator; xcrun simctl bootstatus "$UDID"
```

이미 부팅되어 있으면 `boot`가 에러를 내지만 무해하다.

## Run (agent path) — 드라이버로 조작·검증

앱을 실제 시뮬레이터에서 구동해 유저 플로우(건설 → 라면 선택 → 맵 배치 → 매출 500원 차감)를
탭 단위로 실행·검증한다. 코드 변경이 실제 앱에서 동작하는지 볼 때 이걸 먼저 쓴다:

```bash
fvm flutter test integration_test/smoke_test.dart -d "$UDID"
```

약 30초(증분 빌드 기준), 마지막 줄 `All tests passed!`가 성공 판정. 새 플로우를 검증하려면
`integration_test/smoke_test.dart`에 testWidgets를 추가한다 — 아래 Gotchas의 pump 규칙 필수.

## Run (관찰용 실행) — 실행 + 스크린샷 + 핫 리로드

앱을 띄워놓고 화면을 관찰하거나 코드 수정을 핫 리로드로 반영할 때. tmux가 없는 환경이므로
`--pid-file` + 시그널로 제어한다:

```bash
fvm flutter run -d "$UDID" --pid-file /tmp/reststop_flutter.pid > /tmp/reststop_run.log 2>&1 &
# 준비 대기 (수십 초; 로그에 "Flutter run key commands"가 뜨면 준비 완료)
# 주의: macOS에는 GNU `timeout`이 없다 — 루프로 폴링할 것
for i in $(seq 1 90); do grep -q "Flutter run key commands" /tmp/reststop_run.log 2>/dev/null && break; sleep 2; done
```

| 조작 | 명령 |
|---|---|
| 핫 리로드 | `kill -USR1 $(cat /tmp/reststop_flutter.pid)` → 로그에 `Reloaded ...` |
| 핫 리스타트 | `kill -USR2 $(cat /tmp/reststop_flutter.pid)` |
| 스크린샷 | `xcrun simctl io "$UDID" screenshot /tmp/shot.png` |
| 종료 | `kill $(cat /tmp/reststop_flutter.pid)` |

스크린샷을 찍었으면 반드시 열어서 확인할 것 — 게임 맵(주황/회색 마름모 타일), 좌상단 시간 HUD,
우상단 `매출 N원`, 하단 `건설` 버튼이 보여야 정상 렌더링이다.

## Test

유닛 테스트는 없다 (`test/` 디렉토리 없음). 위의 integration test가 유일한 테스트다.
`fvm flutter analyze`는 통과 상태 유지.

## Gotchas

- **Flame 게임에서 `pumpAndSettle()`은 영원히 끝나지 않는다** — 게임 루프가 매 프레임 새 프레임을
  스케줄하기 때문. integration test에서는 반드시 고정 시간 `pump(Duration(...))`만 쓸 것.
- **`simctl`로는 탭을 보낼 수 없다** — 스크린샷/부팅만 가능. 탭·제스처 검증은 integration test로.
- **건설 화면의 아이템은 두 번 탭해야 선택된다** — 첫 탭은 미리보기 시트, 같은 타일 재탭이 확정.
  이때 시트 제목에도 같은 텍스트가 있으므로 finder는 `find.descendant(of: find.byType(GridView), ...)`로 좁힌다.
- **배치 탭 위치**: 배치 대상은 탭한 곳이 아니라 카메라 중앙에서 가장 가까운 유효 타일이다.
  앱 초기 카메라는 타일 2147 중앙이므로 `GameWidget` 중앙 탭이 곧 배치 확정 탭이 된다.
- **pid 파일은 flutter run 종료 시 자동 삭제된다** — 파일이 없으면 프로세스가 이미 죽은 것.
  시뮬레이터에서 앱을 (사람이) 종료하면 flutter run도 `Lost connection to device.`를 남기고 스스로 종료된다.

## Troubleshooting

- **`fvm flutter` 실행이 `Would you like to install it now? (y/n)`에서 멈춤**: FVM 캐시에 3.32.6이 없음.
  `fvm install 3.32.6` 후 재시도.
- **`Error (Xcode): Unable to load contents of file list: ... Pods-Runner-*-input-files.xcfilelist`**:
  `ios/Pods` 미설치 (새 worktree/클론). `cd ios && LANG=en_US.UTF-8 pod install`.
- **`flutter: command not found`**: 이 머신에는 flutter가 PATH에 없다. 항상 `fvm flutter`.
