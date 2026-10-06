# 도시 탐방 규격 (병렬 작업용 계약서)

도시에 도착한 뒤의 흐름, 데이터 형식, 함수 이름, 담당 파일을 정한다. 여러 세션이 동시에 작업하므로 **자기 담당이 아닌 파일은 고치지 않는다.** 여기 적힌 이름과 형식은 바꾸지 않는다. 바꿔야 하면 작업 보고에 이유와 함께 적는다.

## 1. 흐름

```
큰 지도(WorldMapScreen) --이동--> 이동 이벤트 --> 도시 도착 장면(CityArrival)
  --> 도착 대화/이벤트 --> 도시 거리(TownView): 옆에서 본 거리를 걸어 다닌다
      왼쪽 끝 도시 입구, 구역 입구 4곳, 입구마다 그 구역 NPC가 서 있다 (다가가서 E: 들어가기·말 걸기)
  구역(LocationView): 배경, NPC와 대화, 서비스(거래·정비·소문), 구역 랜덤 이벤트
  도시 입구 --> 큰 지도(전체 화면)로 다음 목적지 선택
```

- 모든 도시에는 거래 구역(`kind: "market"`)이 반드시 하나 있다. 기존 시장 표(사고팔기)가 여기로 옮겨 간다.
- 구역에 처음 들어갈 때 확률로 그 구역 이벤트가 뜬다. 정세 사건과 진영 점유율에 따라 뜨는 이벤트가 달라진다.
- 반복 줄이기 (`economy.json`의 `events`): 한 도시에 머무는 동안 구역 이벤트는 `location_events_per_stay`번까지, 같은 구역에 다시 들어가면 뜨지 않는다. 한 번 뜬 이벤트는 `cooldown_days`일 동안 다시 뜨지 않고, `trigger.once`가 참이면 다시는 안 뜬다.
- 구역마다 NPC가 1명 있다. 대화할 수 있고, 일부는 동료로 영입하거나 의뢰(퀘스트)를 준다.
- 도시에 처음 도착하면 도착 대화 `data/dialogues/arrival_<도시 id>.json`(그 도시 소개)이 나오고, 이후 도착에는 도착 이벤트가 확률로 뜬다. 화면 담당은 `state.visited_cities`로 첫 방문을 판단하고 도착 장면이 끝날 때 기록한다.
- 하루 규칙: 구역 이동은 시간을 쓰지 않는다. 도시를 떠날 때만 날이 흐른다 (이동 일수만큼).

## 2. 데이터 형식

모든 식별자는 영문 snake_case, 표시 이름은 한국어. 요구 조건(`requires`)과 효과(`effects`)는 이벤트와 같은 형식을 쓴다 (`scripts/core/defs.gd`, `docs/design.md` 이벤트 절).

### 2.1 `data/locations.json` (명단은 3절, 이미 작성됨)

```json
{ "id": "helios_market", "city": "helios", "kind": "market", "name": "배급 시장",
  "description": "한 줄 소개", "services": ["trade"], "npc": "ration_clerk" }
```

- `kind`: market, hq, workshop, tavern, slum, plaza, special 중 하나.
- `services`: `trade`(시장 표), `repair`(정비), `rumors`(소문 듣기), `recruit`(용병 고용) 중 0개 이상.
- 배경 그림: `res://assets/art/locations/<location id>.png` (640x360). 없으면 도시 배경을 쓴다.

### 2.1.1 `data/towns.json` (도시 거리 배치)

```json
{ "id": "helios", "gate": 95, "ground": 334, "npc_offset": 34,
  "doors": { "helios_market": 280, "helios_plaza": 450, "helios_hq": 628, "helios_outskirts": 796 },
  "folk": ["porter", "old_woman", "kid", "worker"] }
```

- 좌표는 거리 그림의 원래 픽셀. `gate`: 도시 입구 x, `ground`: 발이 닿는 y, `doors`: 구역 입구 x, `npc_offset`: NPC가 입구에서 떨어져 서는 거리.
- 거리 그림: `res://assets/art/towns/<도시 id>.png` (높이 360, 폭 약 850. 없으면 도시 배경을 쓴다).
- 인물: 주인공 걷기 `assets/town/player_0~3.png`, NPC `assets/town/npcs/<npc id>.png`, 행인 `assets/town/folk/<이름>.png` (키 약 48). 원본과 변환은 `art_src/build_town_art.py`.

### 2.2 `data/npcs.json` (명단은 3절, 이미 작성됨)

```json
{ "id": "ration_clerk", "name": "배급관 오르", "city": "helios", "location": "helios_market",
  "role": "배급 시장 관리인", "faction": "victor", "dialogue": "ration_clerk", "companion": "" }
```

- 초상화: `res://assets/portraits/<npc id>.png` (48x48). 없으면 이름 첫 글자 틀을 그린다.
- `dialogue`: 대화 파일 id (`data/dialogues/<id>.json`).
- `companion`: 영입 가능한 동료면 `data/companions.json`의 id, 아니면 "".
- 선택 `requires`: 조건이 맞을 때만 그 구역에 나타난다 (예: 동료로 영입된 뒤에는 사라짐).

### 2.3 `data/dialogues/<id>.json`

```json
{
  "id": "ration_clerk",
  "start": "greet",
  "nodes": {
    "greet": {
      "speaker": "ration_clerk",
      "text": "대사. {player}는 주인공 이름으로 바뀐다.",
      "effects": [],
      "choices": [
        { "text": "선택지", "requires": [], "cost": [], "check": { "stat": "negotiation", "dc": 13 },
          "next": "node_id", "fail_next": "node_id", "effects": [], "fail_effects": [] },
        { "text": "대화를 끝낸다", "next": "" }
      ]
    }
  },
  "variants": [
    { "requires": [ { "type": "flag", "flag": "met_ration_clerk" } ], "start": "again" }
  ]
}
```

- `speaker`: NPC id 또는 `"player"`, `"narrator"`.
- `next`가 ""이면 대화 끝. `check`가 있으면 성공 시 `next`/`effects`, 실패 시 `fail_next`/`fail_effects`.
- `variants`: 위에서부터 조건이 맞는 첫 항목의 `start`로 시작한다. 없으면 `start`.
- 노드의 `effects`는 그 노드에 들어설 때 적용된다.

### 2.4 새 요구 조건 타입 (엔진 담당이 구현)

| type | 필드 | 뜻 |
| --- | --- | --- |
| `crisis` | `crisis`, `active` (bool, 기본 true) | 정세 사건 진행 여부 |
| `faction_share` | `faction`, `min`/`max` (0~1) | 진영 점유율 |
| `quest` | `quest`, `state` (`none`/`active`/`done`) | 의뢰 상태 |
| `companion` | `companion` (id, ""이면 아무나) | 지금 태운 동료 |
| `day` | `min`/`max` | 날짜 |
| `power` | `min` | 전력 보유량 |

기존: `cargo`, `module`, `reputation`, `faction_reputation`, `flag`. `flag`는 `"set": false`를 주면 플래그가 없을 때 참이다.

숫자 조건(`reputation`, `faction_reputation`, `faction_share`, `day`, `power`)은 모두 `min`과 `max`를 둘 다 받는다 (하나만 써도 된다).

### 2.5 새 효과 타입 (엔진 담당이 구현)

| type | 필드 | 뜻 |
| --- | --- | --- |
| `start_dialogue` | `dialogue` | 이 결과 뒤에 대화를 연다 |
| `recruit` | `companion` | 동료 영입 (이미 있으면 교체 여부를 묻지 않고 기존 동료를 내린다) |
| `dismiss` | 없음 | 지금 동료를 내린다 |
| `quest_start` | `quest` | 의뢰 시작 |
| `quest_complete` | `quest` | 의뢰 완료, 보상 적용 |
| `trust` | `delta` | 지금 동료의 신뢰 변화 |
| `faction_strength` | `faction`, `delta` | 진영 세력 변화 |

기존: `reputation`, `power`, `cargo_add`, `cargo_remove`, `vehicle_damage`, `flag_set`, `flag_clear`, `start_combat`.

### 2.6 이벤트 트리거 추가

기존 이벤트 파일 형식 그대로, `trigger.on`에 두 가지를 더한다.

- `"arrival"`: 도시 도착. `cities` 목록(비우면 모든 도시). 기존 `"city"`는 `"arrival"`과 같게 취급한다.
- `"location"`: 구역에 들어갈 때. `locations`(구역 id 목록) 또는 `kinds`(구역 종류 목록) 중 하나. 둘 다 비우면 모든 구역.
- 정세에 따른 변화는 `trigger.requires`에 `crisis`, `faction_share` 조건을 넣어서 만든다.

### 2.7 `data/quests.json`

```json
{ "id": "beck_first_job", "giver": "aurel_beck", "title": "전력청의 첫 의뢰",
  "summary": "한 줄 설명",
  "objective": { "type": "deliver", "good": "raw_food", "qty": 10, "location": "helios_hq" },
  "reward": [ { "type": "power", "delta": 120 }, { "type": "reputation", "city": "helios", "delta": 10 } ] }
```

- 목표 종류: `deliver`(그 구역에서 화물을 넘김), `visit`(그 구역에 가기), `flag`(플래그가 서면 완료).
- 완료 처리는 구역에 들어갈 때 엔진이 확인하고, 완료 가능하면 그 구역 NPC 대화의 `quest_ready` 조건으로 드러낸다. 대화에서 `quest_complete` 효과로 끝낸다.

### 2.8 `data/companions.json`

```json
{ "id": "ian", "name": "이안", "npc": "ian", "origin": "victor",
  "combat": { "hp": 14, "focus": 3, "might": 1, "weapon": "pistol" },
  "bonus_stat": "tech", "bonus": 2,
  "leave_if": [ { "type": "reputation", "city": "helios", "min": 60 } ],
  "leave_text": "떠날 때 대사" }
```

- 동료는 한 번에 한 명. 동료가 있으면 전투 분대의 임시 용병 자리를 동료가 대신한다.
- `bonus_stat`: 태우고 있으면 그 능력치 판정에 `bonus`를 더한다.
- `leave_if`: 하루가 지날 때 조건 중 하나라도 맞으면 떠난다 (알림 창).

## 3. 명단 (도시 8곳 × 구역 4곳, 구역마다 NPC 1명)

| 도시 | 구역 id | 이름 | 종류 | 서비스 | NPC id | NPC 이름 · 역할 |
| --- | --- | --- | --- | --- | --- | --- |
| 헬리오스 | helios_market | 배급 시장 | market | trade | ration_clerk | 배급관 오르 · 시장 관리인 |
| 헬리오스 | helios_hq | 전력청 | hq | | aurel_beck | 아우렐 벡 · 전력청장 (세력 대표) |
| 헬리오스 | helios_plaza | 검문 광장 | plaza | rumors | sergeant_kade | 케이드 하사 · 검문소 책임자 |
| 헬리오스 | helios_outskirts | 성벽 밖 판자촌 | slum | | lina | 리나 · 배급에서 밀려난 주민 |
| 게이트 7 | gate7_market | 보급창 | market | trade | quartermaster_ro | 로 보급관 |
| 게이트 7 | gate7_garage | 정비고 | workshop | repair | mechanic_juno | 정비사 주노 |
| 게이트 7 | gate7_canteen | 막사 식당 | tavern | rumors | cook_bram | 취사병 브람 |
| 게이트 7 | gate7_command | 지휘소 | hq | | commander_voss | 보스 지휘관 (보조 인물) |
| 언더그리드 | undergrid_market | 암시장 | market | trade | dealer_vex | 암거래상 벡스 |
| 언더그리드 | undergrid_ops | 작전실 | hq | | nova | 노바 · 반란 지도자 (세력 대표) |
| 언더그리드 | undergrid_den | 해커 소굴 | tavern | rumors | piece | 피스 · 해커 (동료 후보) |
| 언더그리드 | undergrid_factory | 조립 공장 | workshop | repair | foreman_dal | 달 공장장 |
| 레드 메사 | red_mesa_market | 탄약 교역소 | market | trade | ammo_trader_sol | 탄약상 솔 |
| 레드 메사 | red_mesa_camp | 용병 모닥불 | tavern | recruit | han | 한 · 용병 (동료 후보) |
| 레드 메사 | red_mesa_cistern | 절벽 저수조 | special | | keeper_wen | 물지기 웬 |
| 레드 메사 | red_mesa_hall | 원로 회당 | hq | | elder_tarr | 타르 원로 (보조 인물) |
| 러스트벨 | rustbelt_market | 고물 장터 | market | trade | scrap_trader_pim | 고물상 핌 |
| 러스트벨 | rustbelt_guild | 고물상 조합 | hq | | gale | 게일 · 조합장 (세력 대표) |
| 러스트벨 | rustbelt_shanty | 판자촌 | slum | | morae | 모래 · 고물꾼 (동료 후보) |
| 러스트벨 | rustbelt_crane | 크레인 정비소 | workshop | repair | crane_mechanic_ivo | 정비공 이보 |
| 그린하우스 | greenhouse_market | 수확물 창고 | market | trade | produce_trader_mei | 창고지기 메이 |
| 그린하우스 | greenhouse_elder | 원로의 온실 | hq | | soha | 소하 · 원로 (세력 대표) |
| 그린하우스 | greenhouse_tower | 정수탑 | special | | ian | 이안 · 떠돌이 기술자 (동료 후보) |
| 그린하우스 | greenhouse_bunk | 농부 숙소 | tavern | rumors | farmhand_tuk | 일꾼 턱 |
| 스왑밋 | swapmeet_bazaar | 대시장 | market | trade | bazaar_trader_ada | 상인 아다 |
| 스왑밋 | swapmeet_booth | 정보 부스 | hq | rumors | meter | 미터 · 정보상 (세력 대표, 중립) |
| 스왑밋 | swapmeet_inn | 운반꾼 여관 | tavern | recruit | innkeeper_moss | 여관 주인 모스 |
| 스왑밋 | swapmeet_auction | 주차장 경매 | special | | auctioneer_fin | 경매인 핀 |
| 스크랩야드 | scrapyard_market | 장물 시장 | market | trade | fence_rook | 장물아비 룩 |
| 스크랩야드 | scrapyard_fort | 크랭크의 요새 | hq | | crank | 크랭크 · 약탈자 두목 (세력 대표) |
| 스크랩야드 | scrapyard_arena | 투기장 | special | | arena_master_gus | 투기장 주인 거스 |
| 스크랩야드 | scrapyard_graveyard | 전쟁 기계 무덤 | special | | scavenger_nim | 넝마주이 님 |

## 4. 코드 인터페이스

엔진 담당이 구현하고, 화면 담당은 이 이름으로만 부른다. 틀(stub)은 이미 저장소에 있다.

```gdscript
# scripts/core/event_runner.gd
static func pick_arrival_event(state: GameState) -> Dictionary      # 확률 포함, 없으면 {}
static func pick_location_event(state: GameState, location_id: String) -> Dictionary

# scripts/core/dialogue_runner.gd  (class_name DialogueRunner, RefCounted)
func _init(state: GameState, dialogue_id: String)
func current() -> Dictionary        # { speaker, speaker_name, text, choices: [{ text, tags, enabled, blocker }] }
func choose(index: int) -> Dictionary  # { roll_text, effect_lines }  판정 결과와 적용된 효과
func is_finished() -> bool

# scripts/ui/dialogue_view.gd  (extends Control)
signal finished
func start(state: GameState, dialogue_id: String) -> void   # 전체 화면 위에 떠서 대화를 진행, 끝나면 finished

# scripts/core/game_state.gd  (엔진 담당이 추가)
var location: String = ""           # 지금 있는 구역, 도시 거리면 ""
var companion: String = ""          # 태운 동료 id
var trust: Dictionary = {}          # 동료 id -> 신뢰
var quests: Dictionary = {}         # 의뢰 id -> "active" | "done"
var visited_cities: Dictionary = {} # 도시 id -> true (첫 도착 대화용)
func enter_location(location_id: String) -> void
func leave_location() -> void
func locations_here() -> Array      # 지금 도시의 구역 목록 (데이터 순서)
func npc_at(location_id: String) -> Dictionary   # 조건이 맞는 NPC, 없으면 {}
func quest_ready(quest_id: String) -> bool
```

## 5. 담당 파일 (자기 담당만 고친다)

| 담당 | 파일 |
| --- | --- |
| 엔진 (대화·의뢰·동료·이벤트 확장) | `scripts/core/*`, `scripts/autoload/game_data.gd`, `scripts/ui/dialogue_view.gd`, `data/companions.json`, `tests/run_tests.gd` |
| 화면 (도착·거리·구역·큰 지도) | `scripts/ui/*` (dialogue_view.gd 제외), `scenes/*`, `tests/screenshot.gd` |
| 이야기 (대화·이벤트·의뢰 내용) | `data/dialogues/*`, `data/events/*`, `data/quests.json`, `data/npcs.json`과 `data/locations.json`의 설명·대사 필드, `docs/story.md` |
| 그림 (구역 배경·초상화) | `assets/art/locations/*`, `assets/portraits/*`, `art_src/*`, `assets/CREDITS.md` |

- 모든 담당: 작업을 마치면 `tests/run_tests.gd`를 돌리고, 커밋 메시지에 한 일을 적는다. `docs/design.md`는 고치지 않고, 바꾸고 싶은 기획은 보고에 적는다.
- 경로는 모두 `TradeGame/` Godot 프로젝트 기준 (`res://`).
