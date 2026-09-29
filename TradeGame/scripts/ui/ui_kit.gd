extends RefCounted
## 화면들이 같이 쓰는 작은 도우미: 라벨, 버튼, 아이콘, 초상화, 전력 표기.

const UI_ICON := "res://assets/icons/ui/%s.png"
const GOOD_ICON := "res://assets/icons/goods/%s.png"
const PORTRAIT := "res://assets/portraits/%s.png"
const PoliticsBar := preload("res://scripts/ui/politics_bar.gd")
const WorldMap := preload("res://scripts/ui/world_map.gd")

const ROAD_NAMES := { "highway": "간선도로", "wasteland": "황무지", "collapsed": "붕괴 구간" }
const KIND_NAMES := {
	"market": "시장", "hq": "본부", "workshop": "작업장", "tavern": "쉼터",
	"slum": "빈민가", "plaza": "광장", "special": "명소",
}
const SERVICE_NAMES := { "trade": "거래", "repair": "정비", "rumors": "소문", "recruit": "고용" }

const GOOD := Color(0.55, 0.85, 0.5)
const BAD := Color(0.9, 0.45, 0.4)


static func label(text: String, color := PixelTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if color != PixelTheme.TEXT:
		l.add_theme_color_override("font_color", color)
	return l


## 굵은 강조색 제목. size는 12의 배수.
static func title(text: String, size := PixelTheme.SIZE_BODY) -> Label:
	var l := label(text, PixelTheme.ACCENT)
	l.add_theme_font_override("font", PixelTheme.font(true))
	if size != PixelTheme.SIZE_BODY:
		l.add_theme_font_size_override("font_size", size)
	return l


## 폭에 맞춰 줄바꿈하는 라벨. 폭을 주면 띄어쓰기에서만 줄을 바꾼다 (자동 줄바꿈은 한글 낱말 가운데서도 끊는다).
static func wrap(text: String, color := PixelTheme.TEXT, width := 0) -> Label:
	var l := label(text, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if width > 0:
		l.text = break_words(text, width)
		l.custom_minimum_size = Vector2(width, 0)
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## 기본 글꼴 크기로 폭을 재어 띄어쓰기 자리에 줄바꿈을 넣는다.
static func break_words(text: String, width: int, size := PixelTheme.SIZE_BODY) -> String:
	var f := PixelTheme.font()
	var out := PackedStringArray()
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" "):
			var next := word if line == "" else line + " " + word
			if line != "" and f.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				out.append(line)
				line = word
			else:
				line = next
		out.append(line)
	return "\n".join(out)


static func button(text: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.pressed.connect(cb)
	return b


static func icon(path: String, icon_size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = load(path)
	r.custom_minimum_size = icon_size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return r


static func texture_or_null(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


## 반투명 패널. alpha로 배경 그림이 비치는 정도를 정한다.
static func panel(alpha := -1.0) -> PanelContainer:
	var p := PanelContainer.new()
	if alpha >= 0:
		var box := PixelTheme.panel_box()
		box.bg_color.a = alpha
		p.add_theme_stylebox_override("panel", box)
	return p


static func vbox(sep := 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func hbox(sep := 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func spacer(vertical := true) -> Control:
	var c := Control.new()
	if vertical:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## NPC 초상화. 48x48 그림을 2배로, 없으면 진영색 틀에 이름 첫 글자. 틀은 1픽셀(화면 2픽셀).
static func portrait(npc: Dictionary) -> Control:
	var tex := texture_or_null(PORTRAIT % npc.get("id", ""))
	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.09, 0.08, 0.11)
	box.border_color = faction_color(npc.get("faction", "")).darkened(0.25)
	box.set_border_width_all(2)
	box.anti_aliasing = false
	frame.add_theme_stylebox_override("panel", box)
	frame.custom_minimum_size = Vector2(100, 100)
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.custom_minimum_size = Vector2(96, 96)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		frame.add_child(r)
	else:
		var l := title(str(npc.get("name", "?")).left(1), 48)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame.add_child(l)
	return frame


## 진영 정세: 진행 중인 사건 이름과 점유율 막대.
static func politics_block(state: GameState) -> Control:
	var box := vbox(6)
	var row := hbox()
	box.add_child(row)
	var t := label("진영 정세", PixelTheme.TEXT_DIM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var crises: Array = state.politics.active.values().map(func(c): return c.name)
	var c := label(", ".join(crises) if not crises.is_empty() else "큰 사건 없음",
		PixelTheme.ACCENT if not crises.is_empty() else PixelTheme.TEXT_DIM)
	row.add_child(c)
	var bar := PoliticsBar.new()
	bar.politics = state.politics
	bar.custom_minimum_size = Vector2(0, 24)
	box.add_child(bar)
	return box


static func faction_color(faction: String) -> Color:
	return WorldMap.FACTION_COLORS.get(faction, Color.WHITE)


## 자식을 모두 지운다. 버튼 신호 안에서도 부를 수 있게 떼어 내지 않고 숨겨서 지운다.
static func clear(node: Node) -> void:
	for c in node.get_children():
		if c is CanvasItem:
			c.visible = false
		c.queue_free()


static func city_name(id: String) -> String:
	return GameData.cities[id].name


static func goods_names(ids: Array) -> String:
	if ids.is_empty():
		return "없음 (모든 물품을 평균가에 거래)"
	return ", ".join(ids.map(func(id): return GameData.goods[id].name))


## 셀 단위 전력을 "12팩 3셀" 형태로.
static func fmt_power(cells: int) -> String:
	var per_pack: int = GameData.economy.currency.cells_per_pack
	var packs := cells / per_pack
	var rest := cells % per_pack
	if packs == 0:
		return "%d셀" % rest
	return "%d팩 %d셀" % [packs, rest] if rest > 0 else "%d팩" % packs


static func reputation_word(rep: int) -> String:
	if rep >= 50:
		return "신뢰"
	if rep >= 20:
		return "우호"
	if rep > -20:
		return "보통"
	if rep > -50:
		return "경계"
	return "적대"
