# TradeGame

2D 턴제 교역 RPG "잔류전력 (가제)". 대항해시대식 교역·탐험 구조를 사이버펑크 폐허로 옮긴 게임.

## 기획

- 기획서: [docs/design.md](docs/design.md). 구현 전 해당 섹션을 먼저 읽고 기획과 맞춰 작업할 것.
- 원본은 Claude Docs 문서(https://claude.ai/artifact/Wu4G29iTnwik7uW7p2jr8o). 기획이 바뀌면 `docs/design.md`도 같이 갱신한다.
- 미정 사항은 `docs/design.md` 마지막 "미정 사항" 체크리스트에 있다. 미정 항목에 걸리는 구현은 임의로 정하지 말고 먼저 물어볼 것.

## 엔진

- Godot 4.7.2, GDScript, 렌더러 GL Compatibility. Godot 프로젝트 루트는 `TradeGame/` 하위 폴더다 (`res://` = `TradeGame/TradeGame/`).
- 실행 파일: `C:\Users\USER\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`
- 테스트 (헤드리스, 종료 코드 0 = 통과):

  ```bash
  "/c/Users/USER/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" --headless --path "D:/github_repo/TradeGame/TradeGame" --script res://tests/run_tests.gd
  ```

- 화면 확인: `--headless` 없이 `--script res://tests/screenshot.gd -- <저장경로.png>`로 메인 화면 스크린샷을 저장한다.
- 배포: `main`에 push하면 `.github/workflows/deploy-web.yml`이 웹 빌드를 만들어 GitHub Pages(https://lastgamer05.github.io/TradeGame/)에 올린다. 한글 폰트(Nanum Gothic)는 CI에서 받아 넣는다. 로컬은 시스템 폰트로 대체된다.
- 새 `class_name`을 추가한 뒤에는 같은 명령에 `--import`를 붙여 한 번 돌려 클래스 캐시를 갱신한다.
- 사용자가 에디터를 열어 둔 상태면 `project.godot`을 직접 고치지 말 것. 에디터가 덮어쓴다.

## 구조

- `data/*.json`: 정적 게임 데이터 (진영, 교역품, 도시, 모듈, 경제 수치). `data/events/*.json`: 이벤트 하나당 파일 하나.
- `scripts/autoload/game_data.gd`: `GameData` autoload. JSON을 읽어 id로 색인하고 참조 무결성을 검증한다.
- `scripts/core/defs.gd`: 데이터에서 쓰는 고정 식별자 (능력치, 도로 종류, 요구 조건·효과 타입). 새 타입은 여기와 `GameData` 검증에 같이 추가한다.
- `scripts/core/game_state.gd`, `market.gd`: 한 판의 상태(전력, 화물, 날짜, 이동)와 도시별 시세. UI와 분리돼 있어 테스트에서 직접 쓴다.
- `scripts/ui/`, `scenes/main.tscn`: 교역 루프 프로토타입 화면. UI는 코드로 만든다.
- `data/routes.json`: 임시 지도 (도시 좌표, 도로). 월드맵 초안이 정해지면 교체한다.
- `tests/run_tests.gd`: 헤드리스 테스트 실행기. 데이터를 고치면 테스트를 돌려 검증 오류가 없는지 확인한다.

## 데이터 규칙

- 식별자는 영문 snake_case, 표시 이름은 한국어.
- 가격과 전력은 셀 단위 정수로 저장한다. 환산 비율은 `data/economy.json`에 있다.
- `economy.json`의 수치와 `goods.json`의 `base_price`는 임시 밸런스 값이다.
