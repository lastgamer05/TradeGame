class_name Defs
extends RefCounted
## 데이터 파일에서 쓰는 고정 식별자 모음. 새 값을 쓰려면 여기에 먼저 추가한다.

const STATS := ["driving", "mechanics", "hacking", "negotiation", "might", "survival"]
const STAT_NAMES := {
	"driving": "운전", "mechanics": "기계", "hacking": "해킹",
	"negotiation": "교섭", "might": "완력", "survival": "생존",
}

const ROAD_TYPES := ["highway", "wasteland", "collapsed"]

const GOOD_CATEGORIES := ["necessity", "tech", "strategic", "info", "contraband"]

## 판정 결과 3단계. 판정이 없는 선택지는 success만 쓴다.
const OUTCOMES := ["success", "partial", "failure"]

const EVENT_TRIGGERS := ["travel", "city", "ruin"]

const REQUIREMENT_TYPES := ["cargo", "module", "reputation", "faction_reputation", "flag", "companion", "animal"]

const COST_TYPES := ["power", "cargo"]

const EFFECT_TYPES := [
	"reputation", "power", "cargo_add", "cargo_remove", "vehicle_damage",
	"companion_trust", "flag_set", "flag_clear", "start_combat",
]
