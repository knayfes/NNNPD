extends Node

var selected_class: String = "Knight"
var selected_difficulty: String = "Normal"
var selected_map: String = "Catacombs"

const SAVE_PATH := "user://dragon_progression.cfg"
const HEROES := ["Knight", "Ranger", "Mage"]
const SKILL_NODES: Array[Dictionary] = [
	{"id": "vitality_1", "title": "Живучесть I", "description": "+15 к максимальному HP", "branch": "vitality", "tier": 1},
	{"id": "vitality_2", "title": "Живучесть II", "description": "+20 к максимальному HP", "branch": "vitality", "tier": 2},
	{"id": "vitality_3", "title": "Живучесть III", "description": "+30 к максимальному HP", "branch": "vitality", "tier": 3},
	{"id": "power_1", "title": "Сила I", "description": "+1 урон атаки", "branch": "power", "tier": 1},
	{"id": "power_2", "title": "Сила II", "description": "+1 урон атаки", "branch": "power", "tier": 2},
	{"id": "power_3", "title": "Сила III", "description": "+2 урона атаки", "branch": "power", "tier": 3},
	{"id": "haste_1", "title": "Стремительность I", "description": "-8% к перезарядке атаки", "branch": "haste", "tier": 1},
	{"id": "haste_2", "title": "Стремительность II", "description": "-10% к перезарядке атаки", "branch": "haste", "tier": 2},
	{"id": "haste_3", "title": "Стремительность III", "description": "-12% к перезарядке атаки", "branch": "haste", "tier": 3},
	{"id": "guard_1", "title": "Защита I", "description": "-1 урон от врагов", "branch": "guard", "tier": 1},
	{"id": "guard_2", "title": "Защита II", "description": "-1 урон от врагов", "branch": "guard", "tier": 2},
	{"id": "guard_3", "title": "Защита III", "description": "-1 урон от врагов", "branch": "guard", "tier": 3}
]

var hero_progress: Dictionary = {}
var inventory: Array[Dictionary] = [
	{"id": "health_potion", "name": "Зелье здоровья", "description": "Восстанавливает здоровье между походами", "count": 3},
	{"id": "iron_ring", "name": "Железное кольцо", "description": "Трофей за победу над боссом", "count": 0},
	{"id": "frost_amulet", "name": "Ледяной амулет", "description": "Редкая награда за сложный поход", "count": 0}
]

func _ready() -> void:
	_create_default_progress()
	_load_progress()

func _create_default_progress() -> void:
	for hero in HEROES:
		if not hero_progress.has(hero):
			hero_progress[hero] = {"level": 1, "xp": 0, "skill_points": 0, "skills": {}}

func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	for hero in HEROES:
		var saved = config.get_value("heroes", hero, null)
		if saved is Dictionary:
			hero_progress[hero] = saved
	var saved_inventory = config.get_value("inventory", "items", null)
	if saved_inventory is Array:
		inventory.clear()
		for item in saved_inventory:
			if item is Dictionary:
				inventory.append(item)

func save_progress() -> void:
	var config := ConfigFile.new()
	for hero in HEROES:
		config.set_value("heroes", hero, hero_progress[hero])
	config.set_value("inventory", "items", inventory)
	config.save(SAVE_PATH)

func get_hero_progress(hero: String) -> Dictionary:
	_create_default_progress()
	return hero_progress.get(hero, hero_progress["Knight"])

func get_stat(hero: String, stat: String) -> int:
	var progress := get_hero_progress(hero)
	var value := 0
	for node in SKILL_NODES:
		if progress["skills"].get(node["id"], false):
			match node["id"]:
				"vitality_1": value += 15 if stat == "max_hp" else 0
				"vitality_2": value += 20 if stat == "max_hp" else 0
				"vitality_3": value += 30 if stat == "max_hp" else 0
				"power_1", "power_2": value += 1 if stat == "damage" else 0
				"power_3": value += 2 if stat == "damage" else 0
				"guard_1", "guard_2", "guard_3": value += 1 if stat == "guard" else 0
	return value

func get_attack_cooldown_multiplier(hero: String) -> float:
	var progress := get_hero_progress(hero)
	var reduction := 0.0
	if progress["skills"].get("haste_1", false):
		reduction += 0.08
	if progress["skills"].get("haste_2", false):
		reduction += 0.10
	if progress["skills"].get("haste_3", false):
		reduction += 0.12
	return maxf(0.55, 1.0 - reduction)

func complete_run(hero: String, difficulty: String) -> int:
	var reward: int = {"Easy": 100, "Normal": 180, "Hard": 300}.get(difficulty, 180)
	var progress := get_hero_progress(hero)
	progress["xp"] += reward
	while progress["xp"] >= _xp_to_next_level(progress["level"]):
		progress["xp"] -= _xp_to_next_level(progress["level"])
		progress["level"] += 1
		progress["skill_points"] += 1
	hero_progress[hero] = progress
	_add_item("iron_ring", 1)
	if difficulty == "Hard":
		_add_item("frost_amulet", 1)
	save_progress()
	return reward

func _xp_to_next_level(level: int) -> int:
	return 100 + (level - 1) * 75

func get_xp_to_next_level(level: int) -> int:
	return _xp_to_next_level(level)

func can_buy_skill(hero: String, skill_id: String) -> bool:
	var progress := get_hero_progress(hero)
	if progress["skills"].get(skill_id, false) or progress["skill_points"] <= 0:
		return false
	for node in SKILL_NODES:
		if node["id"] == skill_id and node["tier"] > 1:
			var previous_id := "%s_%d" % [node["branch"], node["tier"] - 1]
			return progress["skills"].get(previous_id, false)
	return true

func buy_skill(hero: String, skill_id: String) -> bool:
	if not can_buy_skill(hero, skill_id):
		return false
	var progress := get_hero_progress(hero)
	progress["skills"][skill_id] = true
	progress["skill_points"] -= 1
	hero_progress[hero] = progress
	save_progress()
	return true

func _add_item(item_id: String, amount: int) -> void:
	for item in inventory:
		if item["id"] == item_id:
			item["count"] += amount
			return
