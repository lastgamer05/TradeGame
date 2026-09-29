class_name DialogueRunner
extends RefCounted
## 대화 진행기 (docs/city_spec.md 2.3, 4절).
## 시작 노드는 variants 중 조건이 맞는 첫 항목, 없으면 start. 노드에 들어설 때 그 노드의 effects를 적용한다.
## 선택지가 없는 노드는 choose(0)으로 노드의 next(없으면 끝)로 간다.
## 선택지: requires가 안 맞거나 비용이 모자라면 막힌 채 보인다 (hide_if_blocked: true면 숨긴다).
## check가 있으면 d20 판정: 성공은 next/effects, 실패는 fail_next/fail_effects.
## 효과 중 start_dialogue는 이 대화를 거기서 이어 간다 (state.pending_dialogue를 바로 소비한다).

var state: GameState
var dialogue: Dictionary
var dialogue_id: String = ""
var node_id: String = ""
## 지금 노드에 들어서며 적용된 효과 줄. 첫 노드의 것은 화면이 current().entry_lines로 보여 준다.
var entry_lines: Array = []


func _init(game_state: GameState, id: String) -> void:
	state = game_state
	_open(id)


## { speaker, speaker_name, text, choices: [{ text, tags, enabled, blocker }], entry_lines }
func current() -> Dictionary:
	if is_finished():
		return {}
	var node: Dictionary = dialogue.nodes[node_id]
	var speaker: String = node.get("speaker", "narrator")
	var choices := []
	for ch in _visible_choices():
		var blocker := EventRunner.choice_blocker(state, ch)
		choices.append({
			"text": _fill(ch.get("text", "")),
			"tags": EventRunner.choice_tags(state, ch),
			"enabled": blocker == "",
			"blocker": blocker,
		})
	return {
		"speaker": speaker,
		"speaker_name": speaker_name(speaker),
		"text": _fill(node.get("text", "")),
		"choices": choices,
		"entry_lines": entry_lines,
	}


## current().choices의 index번째를 고른다. 막힌 선택지면 아무 일도 하지 않는다.
## { roll_text, effect_lines, success }. effect_lines에는 다음 노드에 들어서며 생긴 효과도 들어간다.
func choose(index: int) -> Dictionary:
	var visible := _visible_choices()
	if is_finished():
		return { "roll_text": "", "effect_lines": [], "success": false }
	# 선택지가 없는 노드는 "계속"으로 노드의 next(없으면 끝)로 간다.
	if visible.is_empty():
		_enter(dialogue.nodes[node_id].get("next", ""))
		return { "roll_text": "", "effect_lines": entry_lines.duplicate(), "success": true }
	if index < 0 or index >= visible.size():
		return { "roll_text": "", "effect_lines": [], "success": false }
	var ch: Dictionary = visible[index]
	if EventRunner.choice_blocker(state, ch) != "":
		return { "roll_text": "", "effect_lines": [], "success": false }

	EventRunner.pay_cost(state, ch)
	var success := true
	var roll_text := ""
	if ch.has("check"):
		var roll := EventRunner.roll_check(state, ch.check)
		success = roll.success
		roll_text = roll.text
	var next: String = ch.get("next", "")
	var effects: Array = ch.get("effects", [])
	if not success:
		next = ch.get("fail_next", next)
		effects = ch.get("fail_effects", [])

	var lines := EventRunner.apply_effects(state, effects)
	if state.pending_dialogue != "":
		var other := state.pending_dialogue
		state.pending_dialogue = ""
		_open(other)
	else:
		_enter(next)
	lines.append_array(entry_lines)
	return { "roll_text": roll_text, "effect_lines": lines, "success": success }


func is_finished() -> bool:
	return node_id == "" or not dialogue.get("nodes", {}).has(node_id)


## speaker id를 화면에 보일 이름으로. narrator는 "".
func speaker_name(speaker: String) -> String:
	if speaker == "player":
		return state.player_name
	if speaker == "narrator":
		return ""
	return state.data.npcs.get(speaker, {}).get("name", "")


func _open(id: String) -> void:
	dialogue_id = id
	dialogue = state.data.dialogues.get(id, {})
	var start: String = dialogue.get("start", "")
	for v in dialogue.get("variants", []):
		if EventRunner.requirements_met(state, v.get("requires", [])):
			start = v.start
			break
	_enter(start)


func _enter(id: String) -> void:
	node_id = id
	entry_lines = []
	if is_finished():
		return
	entry_lines = EventRunner.apply_effects(state, dialogue.nodes[id].get("effects", []))
	# 노드 효과가 다른 대화를 열면 그리로 넘어간다.
	if state.pending_dialogue != "":
		var other := state.pending_dialogue
		state.pending_dialogue = ""
		var kept := entry_lines
		_open(other)
		entry_lines = kept + entry_lines


func _visible_choices() -> Array:
	if is_finished():
		return []
	var out := []
	for ch in dialogue.nodes[node_id].get("choices", []):
		if ch.get("hide_if_blocked", false) and EventRunner.choice_blocker(state, ch) != "":
			continue
		out.append(ch)
	return out


func _fill(text) -> String:
	return str(text).replace("{player}", state.player_name)
