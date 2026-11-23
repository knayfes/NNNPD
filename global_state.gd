extends Node

var selected_class: String = "Knight"
var selected_difficulty: String = "Normal"
var selected_map: String = "Catacombs"

const SAVE_PATH := "user://dragon_progression.cfg"
const TEMP_SAVE_PATH := "user://dragon_progression.tmp"
const BACKUP_SAVE_PATH := "user://dragon_progression.bak"
const HEROES: Array[String] = ["Knight", "Ranger", "Mage"]
const RARITY_POWER := {"Common": 1, "Rare": 2, "Epic": 3, "Legendary": 4}

const SKILL_NODES: Array[Dictionary] = [
	{"id": "vitality_1", "title": "Vitality I", "description": "+15 max health", "branch": "vitality", "tier": 1},
	{"id": "vitality_2", "title": "Vitality II", "description": "+20 max health", "branch": "vitality", "tier": 2},
	{"id": "vitality_3", "title": "Vitality III", "description": "+30 max health", "branch": "vitality", "tier": 3},
	{"id": "vitality_4", "title": "Vitality IV", "description": "+40 max health", "branch": "vitality", "tier": 4},
	{"id": "vitality_5", "title": "Second Wind", "description": "+50 max health", "branch": "vitality", "tier": 5},
	{"id": "vitality_6", "title": "Immortal Core", "description": "+1 defense", "branch": "vitality", "tier": 6},
	{"id": "power_1", "title": "Power I", "description": "+1 attack damage", "branch": "power", "tier": 1},
	{"id": "power_2", "title": "Power II", "description": "+1 attack damage", "branch": "power", "tier": 2},
	{"id": "power_3", "title": "Power III", "description": "+2 attack damage", "branch": "power", "tier": 3},
	{"id": "power_4", "title": "Power IV", "description": "+3 attack damage", "branch": "power", "tier": 4},
	{"id": "power_5", "title": "Heavy Blow", "description": "+3 attack damage", "branch": "power", "tier": 5},
	{"id": "power_6", "title": "Executioner", "description": "+4 attack damage", "branch": "power", "tier": 6},
	{"id": "haste_1", "title": "Haste I", "description": "-8% attack cooldown", "branch": "haste", "tier": 1},
	{"id": "haste_2", "title": "Haste II", "description": "-10% attack cooldown", "branch": "haste", "tier": 2},
	{"id": "haste_3", "title": "Haste III", "description": "-12% attack cooldown", "branch": "haste", "tier": 3},
	{"id": "haste_4", "title": "Haste IV", "description": "-8% attack cooldown", "branch": "haste", "tier": 4},
	{"id": "haste_5", "title": "Quick Cast", "description": "-10% ability cooldown", "branch": "haste", "tier": 5},
	{"id": "haste_6", "title": "Momentum", "description": "-12% ability cooldown", "branch": "haste", "tier": 6},
	{"id": "guard_1", "title": "Guard I", "description": "-1 incoming damage", "branch": "guard", "tier": 1},
	{"id": "guard_2", "title": "Guard II", "description": "-1 incoming damage", "branch": "guard", "tier": 2},
	{"id": "guard_3", "title": "Guard III", "description": "-1 incoming damage", "branch": "guard", "tier": 3},
	{"id": "guard_4", "title": "Guard IV", "description": "-1 incoming damage", "branch": "guard", "tier": 4},
	{"id": "guard_5", "title": "Bulwark", "description": "-1 incoming damage", "branch": "guard", "tier": 5},
	{"id": "guard_6", "title": "Thorns", "description": "-1 incoming damage", "branch": "guard", "tier": 6}
]

var hero_progress: Dictionary = {}
var equipped_items: Dictionary = {"Knight": {}, "Ranger": {}, "Mage": {}}
var inventory: Array[Dictionary] = [
	{"id": "health_potion", "name": "Health Potion", "description": "Restores up to 40 health during a run", "count": 3, "icon": "res://game/assets/rewards/icons/Potion1_Filled_Red.png"},
	{"id": "iron_ring", "name": "Iron Ring", "description": "Boss victory trophy", "count": 0, "icon": "res://game/assets/rewards/icons/Ring1.png"},
	{"id": "frost_amulet", "name": "Frost Amulet", "description": "Hard run reward", "count": 0, "icon": "res://game/assets/rewards/icons/Necklace2.png"}
]

func _ready() -> void:
	_create_default_progress()
	_load_progress()

func _create_default_progress() -> void:
	for hero in HEROES:
		if not hero_progress.has(hero):
			hero_progress[hero] = {"level": 1, "xp": 0, "skill_points": 0, "skills": {}}
		if not equipped_items.has(hero) or not (equipped_items[hero] is Dictionary):
			equipped_items[hero] = {}

func _load_progress() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		_ensure_inventory_items()
		for hero in HEROES:
			_normalize_hero_progress(hero)
		return
	for hero in HEROES:
		var saved: Variant = config.get_value("heroes", hero, null)
		if saved is Dictionary:
			hero_progress[hero] = saved
	var saved_inventory: Variant = config.get_value("inventory", "items", null)
	if saved_inventory is Array:
		inventory.clear()
		for item in saved_inventory:
			if item is Dictionary:
				inventory.append(item)
	if config.has_section_key("equipment", "items"):
		var saved_equipment: Variant = config.get_value("equipment", "items")
		if saved_equipment is Dictionary:
			equipped_items = saved_equipment
	_ensure_inventory_items()
	for item in inventory:
		if item.get("category", "") == "Equipment":
			item["power"] = clampi(int(item.get("power", 1)), 1, 4)
	_create_default_progress()
	for hero in HEROES:
		_normalize_hero_progress(hero)

func _normalize_hero_progress(hero: String) -> void:
	var progress: Dictionary = hero_progress.get(hero, {})
	progress["level"] = maxi(1, int(progress.get("level", 1)))
	progress["xp"] = maxi(0, int(progress.get("xp", 0)))
	progress["skill_points"] = maxi(0, int(progress.get("skill_points", 0)))
	if not (progress.get("skills", {}) is Dictionary):
		progress["skills"] = {}
	hero_progress[hero] = progress

func _ensure_inventory_items() -> void:
	var defaults: Array[Dictionary] = [
		{"id": "health_potion", "name": "Health Potion", "description": "Restores up to 40 health during a run", "count": 3, "icon": "res://game/assets/rewards/icons/Potion1_Filled_Red.png"},
		{"id": "iron_ring", "name": "Iron Ring", "description": "Boss victory trophy", "count": 0, "icon": "res://game/assets/rewards/icons/Ring1.png"},
		{"id": "frost_amulet", "name": "Frost Amulet", "description": "Hard run reward", "count": 0, "icon": "res://game/assets/rewards/icons/Necklace2.png"}
	]
	for default_item in defaults:
		var found := false
		for item in inventory:
			if item.get("id", "") == default_item["id"]:
				item["name"] = default_item["name"]
				item["description"] = default_item["description"]
				item["count"] = maxi(0, int(item.get("count", 0)))
				item["icon"] = default_item["icon"]
				found = true
				break
		if not found:
			inventory.append(default_item.duplicate())
	for item in inventory:
		if item.get("category", "") == "Equipment":
			item["icon"] = _equipment_icon_for(str(item.get("slot", "")), str(item.get("rarity", "Common")), str(item.get("hero", "Knight")))

func _equipment_icon_for(slot: String, rarity: String, hero: String = "Knight") -> String:
	if slot == "Weapon":
		if hero == "Ranger":
			return "res://game/assets/rewards/icons/Bow_Golden.png" if rarity == "Legendary" else "res://game/assets/rewards/icons/Bow_Wooden.png"
		if hero == "Mage":
			return "res://game/assets/rewards/icons/Dagger_Golden.png" if rarity == "Legendary" else "res://game/assets/rewards/icons/Dagger.png"
		return "res://game/assets/rewards/icons/Sword_Big_Golden.png" if rarity == "Legendary" else "res://game/assets/rewards/icons/Sword_Big.png"
	if slot == "Boots":
		return "res://game/assets/rewards/icons/Boots_CC-BY_Lorc.png"
	if slot == "Greaves":
		return "res://game/assets/rewards/icons/Greaves_CC-BY_Delapouite.png"
	return "res://game/assets/rewards/icons/Armor_Golden.png" if rarity == "Legendary" else "res://game/assets/rewards/icons/Armor_Metal.png"

func save_progress() -> void:
	_ensure_inventory_items()
	var config := ConfigFile.new()
	for hero in HEROES:
		config.set_value("heroes", hero, hero_progress[hero])
	config.set_value("inventory", "items", inventory)
	config.set_value("equipment", "items", equipped_items)
	if config.save(TEMP_SAVE_PATH) != OK:
		push_error("Unable to save progression")
		return
	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var temp_absolute := ProjectSettings.globalize_path(TEMP_SAVE_PATH)
	var backup_absolute := ProjectSettings.globalize_path(BACKUP_SAVE_PATH)
	if FileAccess.file_exists(backup_absolute):
		DirAccess.remove_absolute(backup_absolute)
	if FileAccess.file_exists(save_absolute):
		DirAccess.rename_absolute(save_absolute, backup_absolute)
	var result := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if result != OK and FileAccess.file_exists(backup_absolute):
		DirAccess.rename_absolute(backup_absolute, save_absolute)
	elif FileAccess.file_exists(backup_absolute):
		DirAccess.remove_absolute(backup_absolute)

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
				"vitality_4": value += 40 if stat == "max_hp" else 0
				"vitality_5": value += 50 if stat == "max_hp" else 0
				"vitality_6": value += 1 if stat == "guard" else 0
				"power_1", "power_2": value += 1 if stat == "damage" else 0
				"power_3": value += 2 if stat == "damage" else 0
				"power_4", "power_5": value += 3 if stat == "damage" else 0
				"power_6": value += 4 if stat == "damage" else 0
				"guard_1", "guard_2", "guard_3", "guard_4", "guard_5", "guard_6": value += 1 if stat == "guard" else 0
	return value + get_equipment_bonus(hero, stat)

func get_attack_cooldown_multiplier(hero: String) -> float:
	var progress := get_hero_progress(hero)
	var reduction := 0.0
	if progress["skills"].get("haste_1", false):
		reduction += 0.08
	if progress["skills"].get("haste_2", false):
		reduction += 0.10
	if progress["skills"].get("haste_3", false):
		reduction += 0.12
	if progress["skills"].get("haste_4", false):
		reduction += 0.08
	return maxf(0.55, 1.0 - reduction)

func get_ability_cooldown_multiplier(hero: String) -> float:
	var progress := get_hero_progress(hero)
	var reduction := 0.0
	if progress["skills"].get("haste_5", false):
		reduction += 0.10
	if progress["skills"].get("haste_6", false):
		reduction += 0.12
	return maxf(0.65, 1.0 - reduction)

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

func consume_item(item_id: String, amount: int = 1) -> bool:
	for item in inventory:
		if item.get("id", "") == item_id and int(item.get("count", 0)) >= amount:
			item["count"] = int(item.get("count", 0)) - amount
			save_progress()
			return true
	return false

func get_item_count(item_id: String) -> int:
	for item in inventory:
		if item.get("id", "") == item_id:
			return int(item.get("count", 0))
	return 0

func add_item(item_id: String, amount: int = 1) -> void:
	if amount > 0:
		_add_item(item_id, amount)
		save_progress()

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
			return progress["skills"].get("%s_%d" % [node["branch"], node["tier"] - 1], false)
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
		if item.get("id", "") == item_id:
			item["count"] = int(item.get("count", 0)) + amount
			return

func get_equipped_item(hero: String, slot: String) -> Dictionary:
	var equipment: Dictionary = equipped_items.get(hero, {})
	var item_id := str(equipment.get(slot, ""))
	for item in inventory:
		if item.get("id", "") == item_id:
			return item
	return {}

func equip_item(item_id: String, hero: String) -> bool:
	for item in inventory:
		if item.get("id", "") == item_id and item.get("category", "") == "Equipment" and item.get("hero", "") == hero:
			var equipment: Dictionary = equipped_items.get(hero, {})
			equipment[str(item.get("slot", ""))] = item_id
			equipped_items[hero] = equipment
			save_progress()
			return true
	return false

func is_item_equipped(item_id: String) -> bool:
	for hero in HEROES:
		if equipped_items.get(hero, {}).values().has(item_id):
			return true
	return false

func get_equipment_bonus(hero: String, stat: String) -> int:
	var bonus := 0
	for slot in ["Weapon", "Chestplate", "Boots", "Greaves"]:
		var item := get_equipped_item(hero, slot)
		var power := int(item.get("power", 0))
		if stat == "damage" and slot == "Weapon":
			bonus += power
		elif stat == "guard" and slot == "Chestplate":
			bonus += 1 + int(power >= 3)
		elif stat == "guard" and slot == "Greaves":
			bonus += 1 + int(power >= 4)
		elif stat == "max_hp" and slot == "Boots":
			bonus += 8 + power * 3
	return bonus

func roll_boss_loot(hero: String, difficulty: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var roll := rng.randf()
	var rarity := "Common"
	match difficulty:
		"Hard":
			if roll >= 0.92: rarity = "Legendary"
			elif roll >= 0.67: rarity = "Epic"
			elif roll >= 0.28: rarity = "Rare"
		"Normal":
			if roll >= 0.97: rarity = "Legendary"
			elif roll >= 0.82: rarity = "Epic"
			elif roll >= 0.48: rarity = "Rare"
		_:
			if roll >= 0.95: rarity = "Epic"
			elif roll >= 0.70: rarity = "Rare"
	var power: int = RARITY_POWER[rarity]
	var slot := "Weapon"
	var icon := "res://game/assets/rewards/icons/Sword.png"
	var model := "res://game/assets/rewards/models/Sword.fbx"
	var item_name := "Knight Blade"
	if rng.randf() < 0.5:
		match hero:
			"Ranger":
				item_name = "Hunter Bow"
				icon = "res://game/assets/rewards/icons/Bow_Golden.png" if rarity == "Legendary" else "res://game/assets/rewards/icons/Bow_Wooden.png"
				model = "res://game/assets/rewards/models/Bow_Golden.fbx" if rarity == "Legendary" else "res://game/assets/rewards/models/Bow_Wooden.fbx"
			"Mage":
				item_name = "Arcane Dagger"
				icon = "res://game/assets/rewards/icons/Dagger_Golden.png" if rarity == "Legendary" else "res://game/assets/rewards/icons/Dagger.png"
				model = "res://game/assets/rewards/models/Dagger_Golden.fbx" if rarity == "Legendary" else "res://game/assets/rewards/models/Dagger.fbx"
			_:
				icon = "res://game/assets/rewards/icons/Sword_Big_Golden.png" if rarity == "Legendary" else "res://game/assets/rewards/icons/Sword_Big.png"
				model = "res://game/assets/rewards/models/Sword_big_Golden.fbx" if rarity == "Legendary" else "res://game/assets/rewards/models/Sword_big.fbx"
	else:
		var slots: Array[String] = ["Chestplate", "Boots", "Greaves"]
		slot = slots[rng.randi_range(0, slots.size() - 1)]
		item_name = "%s %s" % [rarity, slot]
		icon = _equipment_icon_for(slot, rarity, hero)
		model = "res://game/assets/rewards/models/Armor_Leather.fbx" if rarity == "Common" else "res://game/assets/rewards/models/Armor_Metal2.fbx" if rarity == "Epic" or rarity == "Legendary" else "res://game/assets/rewards/models/Armor_Metal.fbx"
	var item := {
		"id": "boss_loot_%d_%d" % [Time.get_ticks_msec(), rng.randi()],
		"name": item_name,
		"description": "%s equipment for %s" % [slot, hero],
		"count": 1,
		"category": "Equipment",
		"slot": slot,
		"hero": hero,
		"rarity": rarity,
		"power": power,
		"icon": icon,
		"model": model
	}
	inventory.append(item)
	save_progress()
	return item
