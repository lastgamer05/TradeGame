class_name DialogueRunner
extends RefCounted
## 대화 진행기 (docs/city_spec.md 2.3, 4절). 틀: 판정, 조건, 효과, variants는 엔진 담당이 채운다.

var state: GameState
var dialogue: Dictionary
var node_id: String = ""


func _init(game_state: GameState, dialogue_id: String) -> void:
	state = game_state
	dialogue = state.data.dialogues.get(dialogue_id, {})
	node_id = dialogue.get("start", "")


## { speaker, speaker_name, text, choices: [{ text, tags, enabled, blocker }] }
func current() -> Dictionary:
	if is_finished():
		return {}
	var node: Dictionary = dialogue.nodes[node_id]
	var speaker: String = node.get("speaker", "narrator")
	var choices := []
	for ch in node.get("choices", []):
		choices.append({ "text": ch.text, "tags": "", "enabled": true, "blocker": "" })
	return {
		"speaker": speaker,
		"speaker_name": state.data.npcs.get(speaker, {}).get("name", ""),
		"text": str(node.get("text", "")).replace("{player}", state.player_name),
		"choices": choices,
	}


## 선택지를 고른다. { roll_text, effect_lines }
func choose(index: int) -> Dictionary:
	var node: Dictionary = dialogue.nodes[node_id]
	var ch: Dictionary = node.choices[index]
	node_id = ch.get("next", "")
	return { "roll_text": "", "effect_lines": [] }


func is_finished() -> bool:
	return node_id == "" or not dialogue.get("nodes", {}).has(node_id)
