# TradeGame

2D 턴제 교역 RPG "잔류전력 (가제)". 대항해시대식 교역·탐험 구조를 사이버펑크 폐허로 옮긴 게임.

## 기획

- 기획서: [docs/design.md](docs/design.md). 구현 전 해당 섹션을 먼저 읽고 기획과 맞춰 작업할 것.
- 원본은 Claude Docs 문서(https://claude.ai/artifact/Wu4G29iTnwik7uW7p2jr8o). 기획이 바뀌면 `docs/design.md`도 같이 갱신한다.
- 미정 사항은 `docs/design.md` 마지막 "미정 사항" 체크리스트에 있다. 미정 항목에 걸리는 구현은 임의로 정하지 말고 먼저 물어볼 것.

## 아트 방향

- 배경, 도시, 캐릭터 모두 픽셀 아트. 황혼·밤의 폐허 도시, 청록·보라회색 하늘에 주황·호박색 불빛, 녹슨 노점, 늘어진 전선, 폐차.
- 이미지 생성은 바르코(VARCO) 커스텀 워크플로에서 GPT 이미지 모델을 쓴다.
- 에셋 출처와 라이선스는 `TradeGame/assets/CREDITS.md`에 기록한다.
- 옛날 16비트풍이 아니라 요즘 픽셀 게임(이스트워드, 씨 오브 스타즈) 느낌: 노이즈·디더링 없는 깔끔한 색 단계, 선명한 픽셀 덩어리, 호박색 림라이트와 청록 그림자. 바르코 프롬프트에 "16-bit"를 쓰지 않는다.
- 픽셀 퍼펙트: 모든 그림은 화면의 절반 해상도(원래 픽셀 크기)로 만들어 두고 정확히 2배, 최근접 필터로 보여 준다. 전투는 640x360 SubViewport, 시장 화면은 `texture_filter = NEAREST`. 부드럽게 늘리거나 줄여서 그리지 않는다.
- 생성 원본은 Godot 프로젝트 밖 `art_src/modern/`, `art_src/combat/modern/`에 두고, `art_src/slice_sheet.py`(마젠타 배경 시트 자르기)와 `art_src/pixelize.py`(원래 픽셀 크기로 줄이기, 색 제한, 외곽선)로 `TradeGame/assets/`에 넣는다. 크기: 도시·바닥 640x360, 유닛 키 32~35, 교역품 아이콘 18x18, 소품 폭은 `battle_view.gd`의 `PROP_WIDTHS`.
- 폰트는 갈무리11(픽셀 폰트, 원본 12px). 크기는 12의 배수만 쓴다. 공용 테마는 `scripts/ui/pixel_theme.gd`.

## 엔진

- Godot 4.7.2, GDScript, 렌더러 GL Compatibility. Godot 프로젝트 루트는 `TradeGame/` 하위 폴더다 (`res://` = `TradeGame/TradeGame/`).
- 실행 파일: `C:\Users\USER\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- 테스트 (헤드리스, 종료 코드 0 = 통과):

  ```bash
  "/c/Users/USER/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/github_repo/TradeGame/TradeGame" --script res://tests/run_tests.gd
  ```

- 화면 확인: `--headless` 없이 `--script res://tests/screenshot.gd -- <저장경로.png>`로 메인 화면 스크린샷을 저장한다.
- 배포: `main`에 push하면 `.github/workflows/deploy-web.yml`이 웹 빌드를 만들어 GitHub Pages(https://lastgamer05.github.io/TradeGame/)에 올린다.- 새 `class_name`을 추가한 뒤에는 같은 명령에 `--import`를 붙여 한 번 돌려 클래스 캐시를 갱신한다.
- 사용자가 에디터를 열어 둔 상태면 `project.godot`을 직접 고치지 말 것. 에디터가 덮어쓴다.

## 구조

- `data/*.json`: 정적 게임 데이터 (진영, 교역품, 도시, 모듈, 경제 수치). `data/events/*.json`: 이벤트 하나당 파일 하나.
- `scripts/autoload/game_data.gd`: `GameData` autoload. JSON을 읽어 id로 색인하고 참조 무결성을 검증한다.
- `scripts/core/defs.gd`: 데이터에서 쓰는 고정 식별자 (능력치, 도로 종류, 요구 조건·효과 타입). 새 타입은 여기와 `GameData` 검증에 같이 추가한다.
- `scripts/core/game_state.gd`, `market.gd`: 한 판의 상태(전력, 화물, 날짜, 이동)와 도시별 시세. UI와 분리돼 있어 테스트에서 직접 쓴다.
- `scripts/core/politics.gd`, `data/politics.json`: 진영 세력과 정세 사건. 거래가 세력을 키우고, 점유율이 문턱을 넘으면 사건이 시작돼 시세 배율이 바뀐다.
- `scripts/combat/battle.gd`, `data/combat.json`: 전투 규칙 (맵 생성, 이동, 시야, 엄폐, 명중, 적 AI, 차량 저격, 종료 조건). 전투 격자는 정육각형(pointy-top, odd-r 오프셋 좌표, 거리·시야는 큐브 좌표). `battle_view.gd`는 전투 화면으로, `Battle.events`(이동, 사격, 피해, 폭발 등)를 차례대로 애니메이션 재생한다. 스프라이트는 `assets/combat/`, 없으면 도형으로 그린다. 화면은 30도 회전·세로 0.58 눌림(`ROT_DEG`, `TILT`)이고, 장소별 바닥 그림(`assets/combat/ground/`)을 칸 안에만 밝게 비춘다. 장애물 풀은 `combat.json`의 `locations.*.props`. 바르코 스프라이트 시트는 `art_src/slice_sheet.py`로 자른다. `tests/balance_sim.gd`로 조우별 승률을 확인한다.
- `scripts/core/event_runner.gd`: 이벤트 선택(이동 후 도로 종류, 도시 도착), 선택지 조건·비용 확인, d20 판정, 효과 적용. `start_combat` 효과는 전투를 띄우고, `vehicle_damage`는 차량 부위를 파손시킨다.
- `scripts/ui/`, `scenes/main.tscn`: 교역 루프 프로토타입 화면. UI는 코드로 만든다.
- `data/routes.json`: 임시 지도 (도시 좌표, 도로). 월드맵 초안이 정해지면 교체한다.
- `tests/run_tests.gd`: 헤드리스 테스트 실행기. 데이터를 고치면 테스트를 돌려 검증 오류가 없는지 확인한다.

## 데이터 규칙

- 식별자는 영문 snake_case, 표시 이름은 한국어.
- 가격과 전력은 셀 단위 정수로 저장한다. 환산 비율은 `data/economy.json`에 있다.
- `economy.json`의 수치와 `goods.json`의 `base_price`는 임시 밸런스 값이다.
