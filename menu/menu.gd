extends Control

const TEXT := Color("#edf3ff")
const MUTED := Color("#9eafd0")
const GOLD := Color("#ffd36e")
const CYAN := Color("#63e6ff")
const PURPLE := Color("#c17cff")
var selected_class := "Knight"
var selected_difficulty := "Normal"
var selected_map := "Catacombs"
var option_buttons: Dictionary = {"class": {}, "difficulty": {}, "map": {}}
var selected_style: StyleBoxFlat
var progression_panel: PanelContainer
var inventory_panel: PanelContainer
var progression_header: Label
var skill_buttons: Dictionary = {}
var inventory_box: VBoxContainer
var summary_label: Label

func _ready() -> void:
	selected_class = GlobalState.selected_class
	selected_difficulty = GlobalState.selected_difficulty
	selected_map = GlobalState.selected_map
	_build_background()
	selected_style = _style(Color("#263b63"), GOLD, 3, 9)
	_build_menu()

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#060b18")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	for i in range(18):
		var star := Label.new()
		star.text = "*" if i % 3 == 0 else "."
		star.position = Vector2(30 + (i * 137) % 1220, 25 + (i * 71) % 620)
		star.add_theme_color_override("font_color", Color(0.48, 0.7, 1.0, 0.24))
		add_child(star)

func _build_menu() -> void:
	var title := Label.new()
	title.text = "DUNGEONS\nOF DRAGON"
	title.position = Vector2(68, 48)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", GOLD)
	add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Выбери героя, сложность и подземелье из восьми комнат."
	subtitle.position = Vector2(72, 185)
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", MUTED)
	add_child(subtitle)
	var left := PanelContainer.new()
	left.position = Vector2(55, 235)
	left.size = Vector2(565, 430)
	left.add_theme_stylebox_override("panel", _style(Color("#0c1731f2"), Color("#63e6ff"), 2, 20))
	add_child(left)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	left.add_child(box)
	var h := Label.new()
	h.text = "ПОДГОТОВКА К ПОХОДУ"
	h.add_theme_font_size_override("font_size", 24)
	h.add_theme_color_override("font_color", GOLD)
	box.add_child(h)
	_add_section(box, "ВЫБЕРИ ГЕРОЯ", ["Knight", "Ranger", "Mage"], "class")
	_add_section(box, "СЛОЖНОСТЬ", ["Easy", "Normal", "Hard"], "difficulty")
	_add_section(box, "ПОДЗЕМЕЛЬЕ", ["Catacombs", "Ice Caves", "Forgotten Temple"], "map")
	var right := PanelContainer.new()
	right.position = Vector2(655, 235)
	right.size = Vector2(570, 430)
	right.add_theme_stylebox_override("panel", _style(Color("#10182ff2"), Color("#c17cff"), 2, 20))
	add_child(right)
	var rbox := VBoxContainer.new()
	rbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rbox.add_theme_constant_override("separation", 16)
	right.add_child(rbox)
	var rh := Label.new()
	rh.text = "НОВЫЙ ПОХОД"
	rh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rh.add_theme_font_size_override("font_size", 22)
	rh.add_theme_color_override("font_color", CYAN)
	rbox.add_child(rh)
	summary_label = Label.new()
	summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_label.add_theme_font_size_override("font_size", 17)
	summary_label.add_theme_color_override("font_color", TEXT)
	rbox.add_child(summary_label)
	_refresh_summary()
	var start := _button("НАЧАТЬ ПОХОД", GOLD)
	start.custom_minimum_size = Vector2(460, 58)
	start.pressed.connect(_start_game)
	rbox.add_child(start)
	var progression := _button("ДЕРЕВО ПРОКАЧКИ", PURPLE)
	progression.pressed.connect(_open_progression)
	rbox.add_child(progression)
	var inventory := _button("ИНВЕНТАРЬ", CYAN)
	inventory.pressed.connect(_open_inventory)
	rbox.add_child(inventory)
	_build_progression_panel()
	_build_inventory_panel()

func _build_progression_panel() -> void:
	progression_panel = PanelContainer.new()
	progression_panel.position = Vector2(30, 28)
	progression_panel.size = Vector2(1220, 664)
	progression_panel.visible = false
	progression_panel.add_theme_stylebox_override("panel", _style(Color("#0a1429f8"), Color("#c17cff"), 2, 18))
	add_child(progression_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	progression_panel.add_child(box)
	var title := Label.new()
	title.text = "ДЕРЕВО ПРОКАЧКИ"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", PURPLE)
	box.add_child(title)
	progression_header = Label.new()
	progression_header.add_theme_font_size_override("font_size", 18)
	progression_header.add_theme_color_override("font_color", GOLD)
	box.add_child(progression_header)
	var root := Label.new()
	root.text = "✦  ЯДРО ГЕРОЯ  ✦\nНовые способности открываются сверху вниз"
	root.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_theme_font_size_override("font_size", 19)
	root.add_theme_color_override("font_color", CYAN)
	box.add_child(root)
	var tree := HBoxContainer.new()
	tree.name = "SkillTree"
	tree.alignment = BoxContainer.ALIGNMENT_CENTER
	tree.add_theme_constant_override("separation", 16)
	box.add_child(tree)
	var branches := [
		["vitality", "♥ ВЕТКА ЖИЗНИ", Color("#ff8396")],
		["power", "⚔ ВЕТКА СИЛЫ", Color("#ffd36e")],
		["haste", "➤ ВЕТКА СКОРОСТИ", Color("#63e6ff")],
		["guard", "◆ ВЕТКА ЗАЩИТЫ", Color("#c17cff")]
	]
	for branch_data in branches:
		var branch_box := VBoxContainer.new()
		branch_box.custom_minimum_size = Vector2(270, 350)
		branch_box.add_theme_constant_override("separation", 4)
		var branch_title := Label.new()
		branch_title.text = branch_data[1]
		branch_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		branch_title.add_theme_font_size_override("font_size", 17)
		branch_title.add_theme_color_override("font_color", branch_data[2])
		branch_box.add_child(branch_title)
		for tier in range(1, 4):
			if tier > 1:
				var connector := Label.new()
				connector.text = "│\n▼"
				connector.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				connector.add_theme_color_override("font_color", MUTED)
				branch_box.add_child(connector)
			var skill_id := "%s_%d" % [branch_data[0], tier]
			var skill_button := Button.new()
			skill_button.custom_minimum_size = Vector2(260, 76)
			skill_button.add_theme_font_size_override("font_size", 14)
			skill_button.pressed.connect(_buy_skill.bind(skill_id))
			skill_buttons[skill_id] = skill_button
			branch_box.add_child(skill_button)
		tree.add_child(branch_box)
	var close := _button("ЗАКРЫТЬ", GOLD)
	close.custom_minimum_size = Vector2(250, 40)
	close.pressed.connect(_close_management)
	box.add_child(close)

func _build_inventory_panel() -> void:
	inventory_panel = PanelContainer.new()
	inventory_panel.position = Vector2(250, 90)
	inventory_panel.size = Vector2(780, 540)
	inventory_panel.visible = false
	inventory_panel.add_theme_stylebox_override("panel", _style(Color("#0a1429f8"), Color("#63e6ff"), 2, 18))
	add_child(inventory_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	inventory_panel.add_child(box)
	var title := Label.new()
	title.text = "ИНВЕНТАРЬ"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", CYAN)
	box.add_child(title)
	inventory_box = VBoxContainer.new()
	inventory_box.add_theme_constant_override("separation", 8)
	box.add_child(inventory_box)
	var close := _button("ЗАКРЫТЬ", GOLD)
	close.custom_minimum_size = Vector2(250, 42)
	close.pressed.connect(_close_management)
	box.add_child(close)

func _open_progression() -> void:
	inventory_panel.visible = false
	progression_panel.visible = true
	_refresh_progression()

func _open_inventory() -> void:
	progression_panel.visible = false
	inventory_panel.visible = true
	_refresh_inventory()

func _close_management() -> void:
	progression_panel.visible = false
	inventory_panel.visible = false

func _refresh_progression() -> void:
	var progress := GlobalState.get_hero_progress(selected_class)
	var next_xp := GlobalState.get_xp_to_next_level(progress["level"])
	progression_header.text = "%s • уровень %d • опыт %d/%d • очки навыков: %d" % [
		{"Knight": "Рыцарь", "Ranger": "Следопыт", "Mage": "Маг"}.get(selected_class, selected_class),
		progress["level"], progress["xp"], next_xp, progress["skill_points"]
	]
	for node in GlobalState.SKILL_NODES:
		var skill_id: String = node["id"]
		var button: Button = skill_buttons[skill_id]
		var purchased: bool = progress["skills"].get(skill_id, false)
		if purchased:
			button.text = "✓ %s\n%s\nИзучено" % [node["title"], node["description"]]
			button.disabled = true
			button.add_theme_stylebox_override("normal", _style(Color("#285b55"), Color("#63e6ff"), 2, 9))
		else:
			button.text = "%s\n%s\nСтоимость: 1 очко" % [node["title"], node["description"]]
			button.disabled = not GlobalState.can_buy_skill(selected_class, skill_id)
			button.add_theme_stylebox_override("normal", _style(Color("#172746"), Color("#c17cff", 0.55), 1, 9))

func _buy_skill(skill_id: String) -> void:
	if GlobalState.buy_skill(selected_class, skill_id):
		_refresh_progression()

func _refresh_inventory() -> void:
	for child in inventory_box.get_children():
		child.queue_free()
	for item in GlobalState.inventory:
		var row := Label.new()
		row.text = "%s  ×%d\n%s" % [item["name"], item["count"], item["description"]]
		row.add_theme_font_size_override("font_size", 20)
		row.add_theme_color_override("font_color", TEXT if item["count"] > 0 else MUTED)
		inventory_box.add_child(row)

func _add_section(box: VBoxContainer, title: String, options: Array[String], kind: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_color_override("font_color", GOLD)
	box.add_child(label)
	var row := HBoxContainer.new()
	box.add_child(row)
	for option in options:
		var labels := {
			"Knight": "Рыцарь", "Ranger": "Следопыт", "Mage": "Маг",
			"Easy": "Лёгкая", "Normal": "Обычная", "Hard": "Сложная",
			"Catacombs": "Катакомбы", "Ice Caves": "Ледяные пещеры",
			"Forgotten Temple": "Забытый храм"
		}
		var b := _button(labels.get(option, option), CYAN if kind != "map" else PURPLE)
		b.custom_minimum_size = Vector2(150, 36)
		option_buttons[kind][option] = b
		if kind == "class":
			b.pressed.connect(_set_class.bind(option))
		elif kind == "difficulty":
			b.pressed.connect(_set_difficulty.bind(option))
		else:
			b.pressed.connect(_set_map.bind(option))
		row.add_child(b)
	_refresh_selection(kind)

func _set_class(value: String) -> void:
	selected_class = value
	_refresh_selection("class")
	_refresh_summary()
	if progression_panel != null and progression_panel.visible:
		_refresh_progression()
func _set_difficulty(value: String) -> void:
	selected_difficulty = value
	_refresh_selection("difficulty")
func _set_map(value: String) -> void:
	selected_map = value
	_refresh_selection("map")
	_refresh_summary()

func _refresh_summary() -> void:
	if summary_label == null:
		return
	var progress := GlobalState.get_hero_progress(selected_class)
	var hero_name: String = {"Knight": "Рыцарь", "Ranger": "Следопыт", "Mage": "Маг"}.get(selected_class, selected_class)
	var difficulty_name: String = {"Easy": "Лёгкая", "Normal": "Обычная", "Hard": "Сложная"}.get(selected_difficulty, selected_difficulty)
	var map_name: String = {"Catacombs": "Катакомбы", "Ice Caves": "Ледяные пещеры", "Forgotten Temple": "Забытый храм"}.get(selected_map, selected_map)
	summary_label.text = "Мышь — камера • WASD — движение • ЛКМ/ПРОБЕЛ — удар\n\n%s\nУровень %d   |   Опыт %d/%d   |   Очки навыков %d\n%s • %s" % [
		hero_name, progress["level"], progress["xp"],
		GlobalState.get_xp_to_next_level(progress["level"]),
		progress["skill_points"], difficulty_name, map_name
	]

func _refresh_selection(kind: String) -> void:
	var selected := selected_class if kind == "class" else selected_difficulty if kind == "difficulty" else selected_map
	for value in option_buttons[kind]:
		var button: Button = option_buttons[kind][value]
		if value == selected:
			button.add_theme_stylebox_override("normal", selected_style)
			button.add_theme_color_override("font_color", GOLD)
		else:
			button.add_theme_stylebox_override("normal", _style(Color("#172746"), Color("#31466e"), 1, 9))
			button.add_theme_color_override("font_color", TEXT)

func _button(value: String, accent: Color) -> Button:
	var b := Button.new()
	b.text = value
	b.custom_minimum_size = Vector2(420, 38)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_stylebox_override("normal", _style(Color("#172746"), Color(accent, 0.4), 1, 9))
	b.add_theme_stylebox_override("hover", _style(Color("#263b63"), accent, 2, 9))
	b.add_theme_stylebox_override("pressed", _style(Color("#304a76"), accent, 2, 9))
	return b

func _style(color: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

func _start_game() -> void:
	GlobalState.selected_class = selected_class
	GlobalState.selected_difficulty = selected_difficulty
	GlobalState.selected_map = selected_map
	get_tree().change_scene_to_file("res://game/main.tscn")
