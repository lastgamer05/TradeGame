class_name Defs
extends RefCounted
## 데이터 파일에서 쓰는 고정 식별자 모음. 새 값을 쓰려면 여기에 먼저 추가한다.

const STATS := ["driving", "tech", "negotiation", "might", "survival", "focus"]
const STAT_NAMES := {
	"driving": "운전", "tech": "기술", "negotiation": "교섭",
	"might": "완력", "survival": "생존", "focus": "집중",
}

const ROAD_TYPES := ["highway", "wasteland", "collapsed"]

const GOOD_CATEGORIES := ["necessity", "tech", "strategic", "info", "contraband"]

## 판정 결과 3단계. 판정이 없는 선택지는 success만 쓴다.
const OUTCOMES := ["success", "partial", "failure"]

const EVENT_TRIGGERS := ["travel", "city", "ruin", "arrival", "location"]

const REQUIREMENT_TYPES := [
	"cargo", "module", "reputation", "faction_reputation", "flag", "companion", "animal",
	"crisis", "faction_share", "quest", "quest_ready", "day", "power",
	"city", "quest_count", "any_crisis",
]

## quest 조건의 state. ready는 맡고 있고 목표를 채운 상태 (quest_ready 조건과 같다).
const QUEST_STATES := ["none", "active", "done", "ready"]

const COST_TYPES := ["power", "cargo"]

const EFFECT_TYPES := [
	"reputation", "power", "cargo_add", "cargo_remove", "vehicle_damage",
	"companion_trust", "flag_set", "flag_clear", "start_combat",
	"start_dialogue", "recruit", "dismiss", "quest_start", "quest_complete", "trust", "faction_strength",
]

## 도시 구역 (docs/city_spec.md 2.1)
const LOCATION_KINDS := ["market", "hq", "workshop", "tavern", "slum", "plaza", "special"]
const LOCATION_SERVICES := ["trade", "repair", "rumors", "recruit"]

const QUEST_OBJECTIVES := ["deliver", "visit", "flag"]

## 대화 speaker 중 NPC id가 아닌 것
const DIALOGUE_SPEAKERS := ["player", "narrator"]
