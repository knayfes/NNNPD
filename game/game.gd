extends Node3D

const ROOM_COUNT := 8
const ROOM_SIZE := 24.0
const ROOM_SPACING := 24.0
const ROOM_WALL_HEIGHT := 9.5
const ROOM_CEILING_Y := 9.7
const PLAYER_SPEED := 6.5
const GRAVITY := 24.0
const ATTACK_RANGE := 4.8
const ATTACK_HALF_ANGLE_COS := 0.5
const MOUSE_SENSITIVITY := 0.003
const ASSET_ROOT := "res://game/assets/models/"
const PLAYER_ASSETS := {
	"Knight": ASSET_ROOT + "player_knight.glb",
	"Ranger": ASSET_ROOT + "player_rogue.glb",
	"Mage": ASSET_ROOT + "player_mage.glb"
}
const ENEMY_ASSET := ASSET_ROOT + "enemy_skeleton.glb"
const FLOOR_ASSET := ASSET_ROOT + "floor_tile.glb"
const WALL_ASSET := ASSET_ROOT + "wall.glb"
const DOOR_ASSET := ASSET_ROOT + "doorway.glb"
const PILLAR_ASSET := ASSET_ROOT + "pillar.glb"

var player: CharacterBody3D
var player_model: Node3D
var player_animation_player: AnimationPlayer
var enemies: Array[CharacterBody3D] = []
var loot: Array[Node3D] = []
var rooms: Array[Vector3] = []
var room_spawned: Array[bool] = []
var room_barriers: Dictionary = {}
var rng := RandomNumberGenerator.new()
var camera_pivot: Node3D
var camera_yaw := 0.0
var camera_pitch := deg_to_rad(-22.0)
var attack_cd := 0.0
var hp: int = 100
var max_hp: int = 100
var kills: int = 0
var gold: int = 0
var paused := false
var hud: Label
var status: Label
var floor_label: Label
var hp_bar: ProgressBar
var pause_panel: PanelContainer
var damage_overlay: ColorRect
var banner_tween: Tween
var player_attack_time := 0.0
var run_completed := false
var pending_run_completion := false
var lighting_time := 0.0
var candle_lights: Array[OmniLight3D] = []
var sword_trail_state: Dictionary = {}

func _ready() -> void:
	rng.randomize()
	max_hp = {"Knight": 140, "Ranger": 105, "Mage": 90}.get(GlobalState.selected_class, 100)
	if GlobalState.selected_difficulty == "Easy":
		max_hp = roundi(max_hp * 1.25)
	elif GlobalState.selected_difficulty == "Hard":
		max_hp = roundi(max_hp * 0.8)
	max_hp += GlobalState.get_stat(GlobalState.selected_class, "max_hp")
	hp = max_hp
	_build_world()
	_build_ui()
	_spawn_player()
	_spawn_room_content()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_show_status("WASD — ходьба • мышь — камера • ЛКМ / SPACE — атака", Color("#64e8ff"))

func _build_world() -> void:
	var world := Node3D.new()
	world.name = "EightRoomDungeon"
	add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#07101f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#594334")
	environment.ambient_light_energy = 0.18
	environment.glow_enabled = true
	environment.glow_intensity = 1.0
	environment_node.environment = environment
	world.add_child(environment_node)
	for room_index in range(ROOM_COUNT):
		var room_position := Vector3(0, 0, 35.0 - room_index * ROOM_SPACING)
		rooms.append(room_position)
		_build_room(world, room_position, room_index)

func _build_room(parent: Node3D, room_position: Vector3, room_index: int) -> void:
	var room := Node3D.new()
	room.name = "Room_%02d" % (room_index + 1)
	room.position = room_position
	parent.add_child(room)
	for x in range(-6, 6):
		for z in range(-6, 6):
			_add_asset(FLOOR_ASSET, room, Vector3(x * 2.0 + 1.0, 0, z * 2.0 + 1.0), Vector3.ONE)
	for side in [-1, 1]:
		for x in range(-6, 6):
			var opening_to_next: bool = side == -1 and room_index < ROOM_COUNT - 1
			var opening_to_previous: bool = side == 1 and room_index > 0
			if (opening_to_next or opening_to_previous) and (x == -1 or x == 0):
				# Continue the wall above the doorway so the raised ceiling
				# does not leave a tall open gap over the door frame.
				for wall_y in [2.5, 5.0, 7.5]:
					_add_asset(
						WALL_ASSET,
						room,
						Vector3(0, wall_y, side * ROOM_SIZE * 0.5),
						Vector3(2.0, 1.0, 1.0)
					)
				continue
			_add_tall_wall(room, Vector3(x * 2.0 + 1.0, 0, side * ROOM_SIZE * 0.5))
		for z in range(-5, 6):
			_add_tall_wall(room, Vector3(side * ROOM_SIZE * 0.5, 0, z * 2.0 + 1.0), deg_to_rad(90.0))
	if room_index < ROOM_COUNT - 1:
		_add_asset(DOOR_ASSET, room, Vector3(0, 0, -ROOM_SIZE * 0.5), Vector3.ONE)
	if room_index > 0:
		_add_asset(DOOR_ASSET, room, Vector3(0, 0, ROOM_SIZE * 0.5), Vector3.ONE, deg_to_rad(180.0))
	_build_room_ceiling(room)
	_build_room_decor(room)
	_build_room_lighting(room)
	_add_room_collision(parent, room_position, room_index)

func _add_tall_wall(parent: Node3D, position: Vector3, rotation_y := 0.0) -> void:
	for wall_y in [0.0, 2.5, 5.0, 7.5]:
		_add_asset(WALL_ASSET, parent, position + Vector3(0, wall_y, 0), Vector3.ONE, rotation_y)

func _build_room_ceiling(room: Node3D) -> void:
	for x in range(-6, 6):
		for z in range(-6, 6):
			var ceiling_tile := _add_asset(
				FLOOR_ASSET,
				room,
				Vector3(x * 2.0 + 1.0, ROOM_CEILING_Y, z * 2.0 + 1.0),
				Vector3.ONE
			)
			ceiling_tile.rotation.x = PI

func _build_room_lighting(room: Node3D) -> void:
	# Wall candles: warm pools of light placed along both long walls.
	for wall_x in [-10.8, 10.8]:
		for wall_z in [-6.0, 6.0]:
			var sconce := Node3D.new()
			sconce.position = Vector3(wall_x, 3.4, wall_z)
			room.add_child(sconce)
			var bracket := MeshInstance3D.new()
			var bracket_mesh := BoxMesh.new()
			bracket_mesh.size = Vector3(0.42, 0.12, 0.12)
			bracket.mesh = bracket_mesh
			bracket.position.x = -0.18 if wall_x < 0.0 else 0.18
			bracket.material_override = _make_surface_material(Color("#55402c"), 0.0)
			sconce.add_child(bracket)
			_add_candle_flame(sconce, Vector3.ZERO, 0.8, 6.5, 1.25)
	# Paired candles above every doorway.
	for door_side in [-1, 1]:
		if (door_side == -1 and room.name == "Room_08") or (door_side == 1 and room.name == "Room_01"):
			continue
		var door_sconce := Node3D.new()
		door_sconce.position = Vector3(0, 4.0, door_side * (ROOM_SIZE * 0.5 - 0.35))
		room.add_child(door_sconce)
		for candle_x in [-1.35, 1.35]:
			var holder := MeshInstance3D.new()
			var holder_mesh := CylinderMesh.new()
			holder_mesh.top_radius = 0.12
			holder_mesh.bottom_radius = 0.16
			holder_mesh.height = 0.12
			holder.mesh = holder_mesh
			holder.position = Vector3(candle_x, 0, 0)
			holder.material_override = _make_surface_material(Color("#5a4028"), 0.0)
			door_sconce.add_child(holder)
			_add_candle_flame(door_sconce, Vector3(candle_x, 0.05, 0), 0.72, 7.5, 1.45)

	# A suspended iron chandelier with four visible flames and a warm light.
	var chandelier := Node3D.new()
	# Hang it well below the ceiling so the ceiling mesh does not block its light.
	chandelier.position = Vector3(0, ROOM_CEILING_Y - 3.0, 0)
	room.add_child(chandelier)
	var chain := MeshInstance3D.new()
	var chain_mesh := CylinderMesh.new()
	chain_mesh.top_radius = 0.025
	chain_mesh.bottom_radius = 0.025
	chain_mesh.height = 0.9
	chain.mesh = chain_mesh
	chain.position.y = 0.45
	chain.material_override = _make_surface_material(Color("#40352b"), 0.0)
	chandelier.add_child(chain)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.5
	ring_mesh.outer_radius = 0.62
	ring.mesh = ring_mesh
	ring.material_override = _make_surface_material(Color("#57432d"), 0.0)
	chandelier.add_child(ring)
	var hub := MeshInstance3D.new()
	var hub_mesh := SphereMesh.new()
	hub_mesh.radius = 0.16
	hub_mesh.height = 0.32
	hub.mesh = hub_mesh
	hub.material_override = _make_surface_material(Color("#57432d"), 0.0)
	chandelier.add_child(hub)
	for candle_offset in [Vector3(-0.42, 0.0, -0.42), Vector3(0.42, 0.0, -0.42), Vector3(-0.42, 0.0, 0.42), Vector3(0.42, 0.0, 0.42)]:
		_add_candle_flame(chandelier, candle_offset, 0.65, 11.0, 2.2)
	# One stronger central light makes the chandelier illumination noticeable
	# on both the floor and the nearby walls.
	var chandelier_light := OmniLight3D.new()
	chandelier_light.name = "ChandelierLight"
	chandelier_light.position.y = -0.1
	chandelier_light.light_color = Color("#ffc176")
	chandelier_light.light_energy = 4.0
	chandelier_light.omni_range = 14.0
	chandelier_light.shadow_enabled = false
	chandelier.add_child(chandelier_light)
	chandelier_light.set_meta("base_energy", 4.0)
	chandelier_light.set_meta("flicker_phase", randf_range(0.0, TAU))
	candle_lights.append(chandelier_light)

func _add_candle_flame(parent: Node3D, position: Vector3, size: float, light_range: float, energy: float) -> void:
	var candle := MeshInstance3D.new()
	var candle_mesh := CylinderMesh.new()
	candle_mesh.top_radius = 0.09 * size
	candle_mesh.bottom_radius = 0.12 * size
	candle_mesh.height = 0.48 * size
	candle.mesh = candle_mesh
	candle.position = position + Vector3(0, 0.24 * size, 0)
	candle.material_override = _make_surface_material(Color("#d5c39b"), 0.0)
	parent.add_child(candle)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.105 * size
	flame_mesh.height = 0.3 * size
	flame.mesh = flame_mesh
	flame.position = position + Vector3(0, 0.56 * size, 0)
	flame.material_override = _make_surface_material(Color("#ff9b36"), 2.5)
	parent.add_child(flame)
	var light := OmniLight3D.new()
	light.position = flame.position
	light.light_color = Color("#ffb45c")
	light.light_energy = energy
	light.omni_range = light_range
	light.shadow_enabled = false
	parent.add_child(light)
	light.set_meta("base_energy", energy)
	light.set_meta("flicker_phase", randf_range(0.0, TAU))
	candle_lights.append(light)

func _make_surface_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	return material

func _build_room_decor(room: Node3D) -> void:
	var layouts: Array = [
		[Vector2(-8, -7), Vector2(8, 7), Vector2(-8, 7), Vector2(8, -7)],
		[Vector2(-7, -7), Vector2(7, -7), Vector2(-7, 7), Vector2(7, 7)],
		[Vector2(-9, 0), Vector2(9, 0), Vector2(0, -8), Vector2(0, 8)],
		[Vector2(-8, -8), Vector2(8, 8)]
	]
	for point in layouts[rng.randi_range(0, layouts.size() - 1)]:
		_add_asset(PILLAR_ASSET, room, Vector3(point.x, 0, point.y), Vector3.ONE)
		_add_box_collision(room, Vector3(point.x, 1.5, point.y), Vector3(1.8, 3.0, 1.8))

func _add_room_collision(parent: Node3D, room_position: Vector3, room_index: int) -> void:
	# Solid floor and boundary colliders match the visible room. Only the
	# doorway-sized openings between adjacent rooms are left clear.
	_add_box_collision(parent, room_position + Vector3(0, -0.25, 0), Vector3(ROOM_SIZE, 0.5, ROOM_SIZE))
	var wall_data: Array = []
	for side in [-1, 1]:
		var has_door: bool = (side == -1 and room_index < ROOM_COUNT - 1) or (side == 1 and room_index > 0)
		if has_door:
			wall_data.append([Vector3(-7.0, ROOM_WALL_HEIGHT * 0.5, side * ROOM_SIZE * 0.5), Vector3(10.0, ROOM_WALL_HEIGHT, 0.5)])
			wall_data.append([Vector3(7.0, ROOM_WALL_HEIGHT * 0.5, side * ROOM_SIZE * 0.5), Vector3(10.0, ROOM_WALL_HEIGHT, 0.5)])
			wall_data.append([Vector3(0, (ROOM_WALL_HEIGHT + 3.0) * 0.5, side * ROOM_SIZE * 0.5), Vector3(4.0, ROOM_WALL_HEIGHT - 3.0, 0.5)])
		else:
			wall_data.append([Vector3(0, ROOM_WALL_HEIGHT * 0.5, side * ROOM_SIZE * 0.5), Vector3(ROOM_SIZE, ROOM_WALL_HEIGHT, 0.5)])
	wall_data.append([Vector3(-ROOM_SIZE * 0.5, ROOM_WALL_HEIGHT * 0.5, 0), Vector3(0.5, ROOM_WALL_HEIGHT, ROOM_SIZE)])
	wall_data.append([Vector3(ROOM_SIZE * 0.5, ROOM_WALL_HEIGHT * 0.5, 0), Vector3(0.5, ROOM_WALL_HEIGHT, ROOM_SIZE)])
	for data in wall_data:
		_add_box_collision(parent, room_position + data[0], data[1])
	_add_box_collision(parent, room_position + Vector3(0, ROOM_CEILING_Y + 0.2, 0), Vector3(ROOM_SIZE, 0.4, ROOM_SIZE))

func _add_box_collision(parent: Node, world_position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = world_position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = rooms[0] + Vector3(0, 1.0, 0)
	player.floor_snap_length = 0.25
	player.floor_max_angle = deg_to_rad(50.0)
	add_child(player)
	player_model = _add_asset(PLAYER_ASSETS.get(GlobalState.selected_class, PLAYER_ASSETS["Knight"]), player, Vector3(0, -1.0, 0), Vector3.ONE)
	player_model.rotation.y = PI
	player_animation_player = _find_animation_player(player_model)
	_play_animation(player_animation_player, ["Idle", "Idle_Combat", "Unarmed_Idle"])
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.55
	capsule.height = 2.0
	shape.shape = capsule
	player.add_child(shape)
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position = Vector3(0, 1.4, 0)
	camera_pivot.top_level = true
	camera_pivot.rotation.y = camera_yaw
	player.add_child(camera_pivot)
	var spring_arm := SpringArm3D.new()
	spring_arm.name = "CameraSpringArm"
	spring_arm.spring_length = 7.0
	spring_arm.margin = 0.2
	spring_arm.rotation.x = camera_pitch
	camera_pivot.add_child(spring_arm)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 60.0
	spring_arm.add_child(camera)

func _spawn_room_content() -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	enemies.clear()
	room_spawned.clear()
	room_spawned.resize(ROOM_COUNT)
	room_spawned.fill(false)
	for barrier in room_barriers.values():
		if is_instance_valid(barrier):
			barrier.queue_free()
	room_barriers.clear()
	# The starting room remains a safe room. Encounters spawn on room entry.
	room_spawned[0] = true

func _enter_room(room_index: int) -> void:
	if room_index <= 0 or room_index >= ROOM_COUNT or room_spawned[room_index]:
		return
	room_spawned[room_index] = true
	var min_enemies := 6
	var max_enemies := 10
	if GlobalState.selected_difficulty == "Easy":
		min_enemies = 3
		max_enemies = 5
	elif GlobalState.selected_difficulty == "Hard":
		min_enemies = 10
		max_enemies = 15
	var room_enemy_count := rng.randi_range(min_enemies, max_enemies)
	for enemy_index in range(room_enemy_count):
		var spawn_position := rooms[room_index] + Vector3(
			rng.randf_range(-9.0, 9.0),
			1.0,
			rng.randf_range(-9.0, 9.0)
		)
		_spawn_enemy(room_index, enemy_index, spawn_position)
	if room_index == ROOM_COUNT - 1:
		_spawn_boss()
	else:
		_add_room_exit_barrier(room_index)
	_show_status("Комната %d: враги появились! Очисти её, чтобы открыть дверь." % (room_index + 1), Color("#ff8396"))

func _add_room_exit_barrier(room_index: int) -> void:
	# Block the forward doorway (negative Z) until this room's encounter is cleared.
	var barrier := StaticBody3D.new()
	barrier.name = "RoomExitBarrier_%d" % room_index
	barrier.position = rooms[room_index] + Vector3(0, 1.5, -ROOM_SIZE * 0.5)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.2, 3.0, 0.8)
	shape.shape = box
	barrier.add_child(shape)
	add_child(barrier)
	room_barriers[room_index] = barrier

func _on_enemy_defeated(enemy: CharacterBody3D) -> void:
	var room_index := int(enemy.get_meta("room_index", -1))
	if room_index < 0 or not room_barriers.has(room_index):
		return
	for remaining_enemy in enemies:
		if is_instance_valid(remaining_enemy) and int(remaining_enemy.get_meta("room_index", -1)) == room_index:
			return
	var barrier = room_barriers[room_index]
	if is_instance_valid(barrier):
		barrier.queue_free()
	room_barriers.erase(room_index)
	_show_status("Комната очищена — дверь открыта", Color("#64e8ff"))

func _spawn_enemy(room_index: int, enemy_index: int, spawn_position: Vector3, is_boss: bool = false) -> void:
	var enemy := CharacterBody3D.new()
	enemy.name = "Boss" if is_boss else "Skeleton_Room_%02d_%02d" % [room_index + 1, enemy_index]
	enemy.position = spawn_position
	var enemy_max_hp := _get_enemy_max_hp(is_boss)
	var enemy_speed := _get_enemy_speed(is_boss)
	enemy.set_meta("hp", enemy_max_hp)
	enemy.set_meta("max_hp", enemy_max_hp)
	enemy.set_meta("is_boss", is_boss)
	enemy.set_meta("room_index", room_index)
	enemy.set_meta("move_speed", enemy_speed)
	enemy.set_meta("attack_cd", 0.0)
	add_child(enemy)
	var model_scale := Vector3.ONE * (1.8 if is_boss else 1.0)
	var model_offset := -1.0 * model_scale.y
	var enemy_model := _add_asset(ENEMY_ASSET, enemy, Vector3(0, model_offset, 0), model_scale)
	enemy_model.rotation.y = PI
	enemy.set_meta("model", enemy_model)
	enemy.set_meta("animation_player", _find_animation_player(enemy_model))
	_play_animation(enemy.get_meta("animation_player") as AnimationPlayer, ["Idle", "Idle_Combat", "Unarmed_Idle"])
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.9 if is_boss else 0.6
	capsule.height = 3.6 if is_boss else 2.1
	shape.shape = capsule
	enemy.add_child(shape)
	enemy.floor_snap_length = 0.25
	_add_enemy_health_bar(enemy)
	enemies.append(enemy)

func _spawn_boss() -> void:
	var boss_position := rooms[ROOM_COUNT - 1] + Vector3(0, 1.8, 0)
	_spawn_enemy(ROOM_COUNT - 1, 0, boss_position, true)

func _get_enemy_max_hp(is_boss: bool) -> int:
	if is_boss:
		return {"Easy": 100, "Normal": 200, "Hard": 350}.get(GlobalState.selected_difficulty, 200)
	return {"Easy": 8, "Normal": 14, "Hard": 22}.get(GlobalState.selected_difficulty, 14)

func _get_enemy_speed(is_boss: bool) -> float:
	var speed: float = {"Easy": 3.0, "Normal": 3.6, "Hard": 4.2}.get(GlobalState.selected_difficulty, 3.6)
	return speed * (1.15 if is_boss else 1.0)

func _add_enemy_health_bar(enemy: CharacterBody3D) -> void:
	var health_bar := Node3D.new()
	health_bar.name = "HealthBar"
	var is_boss: bool = enemy.get_meta("is_boss", false)
	health_bar.position.y = 3.25 if is_boss else 1.95
	var viewport := SubViewport.new()
	viewport.name = "HealthBarViewport"
	viewport.size = Vector2i(400, 86)
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	health_bar.add_child(viewport)
	var bar_control := Control.new()
	bar_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(bar_control)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.position = Vector2(10, 8)
	bar.size = Vector2(380, 70)
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _style(Color("#17121c"), Color("#09080c"), 3, 12))
	bar.add_theme_stylebox_override("fill", _style(Color("#e32945"), Color("#ff7586"), 2, 10))
	bar_control.add_child(bar)
	var value_label := Label.new()
	value_label.name = "HealthValue"
	value_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 30 if is_boss else 26)
	value_label.add_theme_color_override("font_color", Color("#ffffff"))
	value_label.add_theme_color_override("font_shadow_color", Color("#17121c"))
	value_label.add_theme_constant_override("shadow_offset_x", 2)
	value_label.add_theme_constant_override("shadow_offset_y", 2)
	bar_control.add_child(value_label)
	var sprite := Sprite3D.new()
	sprite.name = "HealthBarSprite"
	sprite.texture = viewport.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.0038
	sprite.no_depth_test = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.scale = Vector3.ONE * (1.1 if is_boss else 0.78)
	health_bar.add_child(sprite)
	health_bar.set_meta("progress_bar", bar)
	health_bar.set_meta("value_label", value_label)
	enemy.add_child(health_bar)
	_update_enemy_health_bar(enemy)

func _update_enemy_health_bar(enemy: CharacterBody3D) -> void:
	if not is_instance_valid(enemy):
		return
	var health_bar := enemy.get_node_or_null("HealthBar") as Node3D
	if health_bar == null:
		return
	var progress_bar := health_bar.get_meta("progress_bar") as ProgressBar
	var value_label := health_bar.get_meta("value_label") as Label
	if progress_bar == null or value_label == null:
		return
	var current_hp := maxi(0, int(enemy.get_meta("hp", 0)))
	var max_enemy_hp := maxi(1, int(enemy.get_meta("max_hp", 1)))
	progress_bar.max_value = max_enemy_hp
	progress_bar.value = current_hp
	value_label.text = "%d / %d" % [current_hp, max_enemy_hp]

func _process(delta: float) -> void:
	lighting_time += delta
	for light_index in range(candle_lights.size()):
		var candle_light := candle_lights[light_index]
		if not is_instance_valid(candle_light):
			continue
		var base_energy: float = candle_light.get_meta("base_energy", 1.0)
		var phase: float = candle_light.get_meta("flicker_phase", 0.0)
		candle_light.light_energy = base_energy * (0.9 + 0.1 * sin(lighting_time * 7.0 + phase))
	if paused:
		return
	_update_sword_trails(delta)
	player_attack_time = maxf(0.0, player_attack_time - delta)
	if player_attack_time <= 0.0:
		var player_is_moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.15
		_play_animation(player_animation_player, ["Running_A", "Walking_A", "Walking_B"] if player_is_moving else ["Idle", "Idle_Combat", "Unarmed_Idle"])
	attack_cd = maxf(0.0, attack_cd - delta)
	for enemy in enemies.duplicate():
		if not is_instance_valid(enemy):
			enemies.erase(enemy)
			continue
		var offset: Vector3 = player.global_position - enemy.global_position
		offset.y = 0.0
		var distance := offset.length()
		var enemy_attack_time := maxf(0.0, float(enemy.get_meta("attack_anim_time", 0.0)) - delta)
		enemy.set_meta("attack_anim_time", enemy_attack_time)
		_update_enemy_health_bar(enemy)
		if enemy_attack_time <= 0.0:
			var enemy_is_moving := Vector2(enemy.velocity.x, enemy.velocity.z).length() > 0.15
			_play_animation(enemy.get_meta("animation_player") as AnimationPlayer, ["Running_A", "Walking_A", "Walking_D_Skeletons"] if enemy_is_moving else ["Idle", "Idle_Combat", "Unarmed_Idle"])
		if distance > 1.8 and distance < 14.0:
			enemy.rotation.y = atan2(-offset.x, -offset.z)
		elif distance <= 1.8:
			var cooldown := maxf(0.0, float(enemy.get_meta("attack_cd")) - delta)
			if cooldown <= 0.0:
				var incoming_damage: int = {"Easy": 2, "Normal": 3, "Hard": 5}.get(GlobalState.selected_difficulty, 3)
				if enemy.get_meta("is_boss", false):
					incoming_damage *= 2
				incoming_damage = maxi(1, incoming_damage - GlobalState.get_stat(GlobalState.selected_class, "guard"))
				hp = maxi(0, hp - incoming_damage)
				enemy.set_meta("attack_cd", 0.8)
				_animate_enemy_attack(enemy)
				_show_damage_vignette()
				_show_status("Скелет атакует", Color("#ff8396"))
			else:
				enemy.set_meta("attack_cd", cooldown)
	if hp <= 0:
		hp = 0
		paused = true
		pause_panel.visible = true
		_set_end_panel("ГЕРОЙ ПАЛ", "Нажми R, чтобы начать заново")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_hud()

func _physics_process(delta: float) -> void:
	if paused:
		return
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var to_player := player.global_position - enemy.global_position
		to_player.y = 0.0
		if to_player.length() > 1.8 and to_player.length() < 14.0:
			var move_speed: float = enemy.get_meta("move_speed", 3.6)
			enemy.velocity.x = to_player.normalized().x * move_speed
			enemy.velocity.z = to_player.normalized().z * move_speed
		else:
			enemy.velocity.x = 0.0
			enemy.velocity.z = 0.0
		if not enemy.is_on_floor():
			enemy.velocity.y -= GRAVITY * delta
		else:
			enemy.velocity.y = 0.0
		enemy.move_and_slide()
	var input_vector := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var forward := Vector3(sin(camera_yaw), 0.0, cos(camera_yaw))
	var right := Vector3(forward.z, 0.0, -forward.x)
	# Input.get_vector returns -1 on Y when W/Up is pressed.
	var movement := right * input_vector.x + forward * input_vector.y
	camera_pivot.global_position = player.global_position + Vector3(0, 1.4, 0)
	player.velocity.x = movement.x * PLAYER_SPEED
	player.velocity.z = movement.z * PLAYER_SPEED
	if not player.is_on_floor():
		player.velocity.y -= GRAVITY * delta
	else:
		player.velocity.y = 0.0
	player.move_and_slide()
	_enter_room(_get_player_room_index())
	if Input.is_action_just_pressed("attack") and attack_cd <= 0.0:
		_attack()

func _get_player_room_index() -> int:
	return clampi(int(round((35.0 - player.global_position.z) / ROOM_SPACING)), 0, ROOM_COUNT - 1)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not paused:
		camera_yaw -= event.relative.x * MOUSE_SENSITIVITY
		camera_pitch = clampf(camera_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-42.0), deg_to_rad(-12.0))
		camera_pivot.rotation.y = camera_yaw
		player.rotation.y = camera_yaw
		(camera_pivot.get_node("CameraSpringArm") as SpringArm3D).rotation.x = camera_pitch
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not paused and attack_cd <= 0.0:
		_attack()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE and not paused and attack_cd <= 0.0:
		_attack()
	if event.is_action_pressed("pause") and hp > 0:
		paused = not paused
		pause_panel.visible = paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			if pending_run_completion:
				_return_to_menu()
			else:
				get_tree().reload_current_scene()

func _attack() -> void:
	if attack_cd > 0.0 or player == null:
		return
	var attack_animation := _play_animation(player_animation_player, ["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop", "Unarmed_Melee_Attack_Punch_A"])
	player_attack_time = _animation_length(player_animation_player, attack_animation, 0.65)
	attack_cd = player_attack_time
	attack_cd *= GlobalState.get_attack_cooldown_multiplier(GlobalState.selected_class)
	_spawn_sword_trails()
	var targets: Array[CharacterBody3D] = []
	# The imported hero models face local -Z after their model correction.
	# Match the attack cone to the visible facing direction, not the camera's
	# positive-Z movement reference.
	var forward := -Vector3(sin(camera_yaw), 0.0, cos(camera_yaw)).normalized()
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var offset: Vector3 = enemy.global_position - player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= ATTACK_RANGE and distance > 0.0:
			var direction_to_enemy := offset / distance
			if forward.dot(direction_to_enemy) >= ATTACK_HALF_ANGLE_COS:
				targets.append(enemy)
	if targets.is_empty():
		_show_status("Перед героем нет врагов в радиусе удара", Color("#ffd36e"))
		return
	var damage := (3 if GlobalState.selected_class == "Knight" else 2) + GlobalState.get_stat(GlobalState.selected_class, "damage")
	var defeated_count := 0
	var defeated_boss := false
	for target in targets:
		var enemy_hp := int(target.get_meta("hp")) - damage
		target.set_meta("hp", enemy_hp)
		_update_enemy_health_bar(target)
		if enemy_hp <= 0:
			defeated_count += 1
			var was_boss: bool = target.get_meta("is_boss", false)
			defeated_boss = defeated_boss or was_boss
			enemies.erase(target)
			target.queue_free()
			kills += 1
			gold += 50 if was_boss else 10
			_on_enemy_defeated(target)
	if defeated_boss:
		pending_run_completion = true
		_set_end_panel("БОСС ПОВЕРЖЕН!", "Опыт будет выдан после выхода в меню")
	else:
		_show_status("Меч поразил %d враг%s • Урон %d" % [
			targets.size(), "а" if targets.size() == 1 else "ов", damage
		], Color("#ffd36e"))
		if defeated_count > 0:
			_show_status("Повержено врагов: %d" % defeated_count, Color("#64e8ff"))

func _spawn_sword_trails() -> void:
	var sword := player_model.find_child("1H_Sword", true, false) as Node3D
	if sword == null:
		sword = player_model.find_child("2H_Sword", true, false) as Node3D
	if sword == null:
		return
	_clear_sword_trails()
	var strips: Array[Node3D] = []
	var materials: Array[StandardMaterial3D] = []
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(0.055, 1.5, 0.035)
	for index in range(8):
		var strip_root := Node3D.new()
		strip_root.name = "SwordWindTrail_%02d" % index
		add_child(strip_root)
		strip_root.global_transform = sword.global_transform
		var strip := MeshInstance3D.new()
		strip.mesh = strip_mesh
		strip.position.y = 0.75
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
		material.emission_enabled = true
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 3.5
		strip.material_override = material
		strip_root.add_child(strip)
		strips.append(strip_root)
		materials.append(material)
	sword_trail_state = {
		"sword": sword,
		"strips": strips,
		"materials": materials,
		"history": [],
		"sample_accumulator": 0.0,
		"active_remaining": maxf(0.12, player_attack_time * 0.82),
		"fade_remaining": 0.0
	}

func _update_sword_trails(delta: float) -> void:
	if sword_trail_state.is_empty():
		return
	var sword := sword_trail_state["sword"] as Node3D
	if not is_instance_valid(sword):
		_clear_sword_trails()
		return
	var history: Array = sword_trail_state["history"]
	if sword_trail_state["active_remaining"] > 0.0:
		sword_trail_state["sample_accumulator"] += delta
		if sword_trail_state["sample_accumulator"] >= 0.02:
			sword_trail_state["sample_accumulator"] = 0.0
			history.push_front(sword.global_transform)
			while history.size() > 8:
				history.pop_back()
		sword_trail_state["active_remaining"] -= delta
		if sword_trail_state["active_remaining"] <= 0.0:
			sword_trail_state["fade_remaining"] = 0.18
	else:
		sword_trail_state["fade_remaining"] -= delta
		if sword_trail_state["fade_remaining"] <= 0.0:
			_clear_sword_trails()
			return

	var strips: Array = sword_trail_state["strips"]
	var materials: Array = sword_trail_state["materials"]
	for index in range(strips.size()):
		var strip_root := strips[index] as Node3D
		if not is_instance_valid(strip_root):
			continue
		if not history.is_empty():
			var history_index := mini(index, history.size() - 1)
			strip_root.global_transform = history[history_index]
		var tail_fade := 1.0 - float(index) / float(strips.size()) * 0.58
		var end_fade := 1.0
		if sword_trail_state["active_remaining"] <= 0.0:
			end_fade = clampf(float(sword_trail_state["fade_remaining"]) / 0.18, 0.0, 1.0)
		var material := materials[index] as StandardMaterial3D
		material.albedo_color.a = 0.75 * tail_fade * end_fade

func _clear_sword_trails() -> void:
	if sword_trail_state.is_empty():
		return
	for strip in sword_trail_state.get("strips", []):
		if is_instance_valid(strip):
			strip.queue_free()
	sword_trail_state.clear()

func _animate_enemy_attack(enemy: CharacterBody3D) -> void:
	var animation_player := enemy.get_meta("animation_player") as AnimationPlayer
	if not is_instance_valid(animation_player):
		return
	var attack_animation := _play_animation(animation_player, ["1H_Melee_Attack_Slice_Horizontal", "1H_Melee_Attack_Chop", "Unarmed_Melee_Attack_Punch_A"])
	enemy.set_meta("attack_anim_time", _animation_length(animation_player, attack_animation, 0.65))

func _spawn_attack_effect(world_position: Vector3, color: Color, is_boss: bool) -> void:
	var effect := Node3D.new()
	effect.name = "AttackEffect"
	effect.global_position = world_position
	add_child(effect)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.95
	var slash_material := material.duplicate() as StandardMaterial3D
	slash_material.albedo_color = Color(color, 0.95)
	slash_material.emission = color * 1.6
	var ring_material := material.duplicate() as StandardMaterial3D
	ring_material.albedo_color = Color(color, 0.8)
	ring_material.emission = color * 1.8
	var duration := 0.42 if is_boss else 0.28
	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(0.11, 0.06, 2.3 if is_boss else 1.7)
	for angle in [-0.8, 0.8, 0.0]:
		var streak := MeshInstance3D.new()
		streak.mesh = streak_mesh
		streak.material_override = slash_material
		streak.rotation.y = angle
		streak.rotation.z = -0.18 if angle == 0.0 else 0.0
		effect.add_child(streak)
	for ring_index in range(2 if is_boss else 1):
		var ring := MeshInstance3D.new()
		var ring_mesh := TorusMesh.new()
		ring_mesh.inner_radius = 0.38 + ring_index * 0.22
		ring_mesh.outer_radius = 0.44 + ring_index * 0.22
		ring.mesh = ring_mesh
		ring.material_override = ring_material
		ring.rotation.x = deg_to_rad(90.0)
		ring.position.y = -0.55 + ring_index * 0.12
		effect.add_child(ring)
		var ring_tween := create_tween()
		ring_tween.tween_property(ring, "scale", Vector3.ONE * (2.2 if is_boss else 1.7), duration)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.42 if is_boss else 0.3
	core_mesh.height = core_mesh.radius * 2.0
	core.mesh = core_mesh
	core.material_override = material
	effect.add_child(core)
	for spark_index in range(8 if is_boss else 5):
		var spark := MeshInstance3D.new()
		var spark_mesh := BoxMesh.new()
		spark_mesh.size = Vector3(0.08, 0.08, 0.45 if is_boss else 0.3)
		spark.mesh = spark_mesh
		spark.material_override = slash_material
		spark.rotation.y = TAU * float(spark_index) / float(8 if is_boss else 5)
		spark.rotation.x = -0.35
		effect.add_child(spark)
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 5.0 if is_boss else 3.0
	flash.omni_range = 5.0 if is_boss else 3.5
	effect.add_child(flash)
	effect.scale = Vector3(0.15, 0.15, 0.15)
	var effect_tween := create_tween().set_parallel(true)
	effect_tween.tween_property(effect, "scale", Vector3.ONE * 1.25, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	effect_tween.tween_property(effect, "rotation:y", TAU * 0.35, duration)
	effect_tween.tween_property(flash, "light_energy", 0.0, duration)
	effect_tween.tween_property(material, "albedo_color:a", 0.0, duration)
	effect_tween.tween_property(slash_material, "albedo_color:a", 0.0, duration)
	effect_tween.finished.connect(effect.queue_free)

func _find_animation_player(model: Node3D) -> AnimationPlayer:
	if not is_instance_valid(model):
		return null
	return model.find_child("AnimationPlayer", true, false) as AnimationPlayer

func _play_animation(animation_player: AnimationPlayer, candidates: Array) -> String:
	if not is_instance_valid(animation_player):
		return ""
	var available := animation_player.get_animation_list()
	var chosen := ""
	for candidate in candidates:
		if candidate in available:
			chosen = candidate
			break
	if chosen == "":
		for candidate in candidates:
			for animation_name in available:
				if String(animation_name).ends_with(candidate):
					chosen = animation_name
					break
			if chosen != "":
				break
	if chosen == "":
		return ""
	if animation_player.current_animation != chosen or not animation_player.is_playing():
		animation_player.play(chosen)
	return chosen

func _animation_length(animation_player: AnimationPlayer, animation_name: String, fallback: float) -> float:
	if not is_instance_valid(animation_player) or animation_name == "":
		return fallback
	var animation := animation_player.get_animation(animation_name)
	return maxf(0.2, animation.length)

func _add_asset(path: String, parent: Node, position: Vector3, scale_value: Vector3, rotation_y := 0.0) -> Node3D:
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Asset not found: " + path)
		return Node3D.new()
	var instance := packed.instantiate() as Node3D
	if instance == null:
		return Node3D.new()
	instance.position = position
	instance.scale = scale_value
	instance.rotation.y = rotation_y
	parent.add_child(instance)
	return instance

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	damage_overlay = ColorRect.new()
	damage_overlay.name = "DamageVignette"
	damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_overlay.modulate.a = 0.0
	var vignette_shader := Shader.new()
	vignette_shader.code = """
shader_type canvas_item;

void fragment() {
	float distance_from_center = distance(UV, vec2(0.5));
	float edge = smoothstep(0.28, 0.72, distance_from_center);
	COLOR = vec4(0.78, 0.015, 0.02, edge * 0.55);
}
"""
	var vignette_material := ShaderMaterial.new()
	vignette_material.shader = vignette_shader
	damage_overlay.material = vignette_material
	layer.add_child(damage_overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 22)
	panel.size = Vector2(390, 105)
	panel.add_theme_stylebox_override("panel", _style(Color("#0b1529e6"), Color("#46638e"), 1, 14))
	layer.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size", 20)
	box.add_child(hud)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(330, 14)
	hp_bar.show_percentage = false
	box.add_child(hp_bar)
	var info := Label.new()
	var class_names := {"Knight": "Рыцарь", "Ranger": "Следопыт", "Mage": "Маг"}
	var difficulty_names := {"Easy": "Лёгкая", "Normal": "Обычная", "Hard": "Сложная"}
	var map_names := {"Catacombs": "Катакомбы", "Ice Caves": "Ледяные пещеры", "Forgotten Temple": "Забытый храм"}
	info.text = "%s • %s • %s" % [class_names.get(GlobalState.selected_class, GlobalState.selected_class), difficulty_names.get(GlobalState.selected_difficulty, GlobalState.selected_difficulty), map_names.get(GlobalState.selected_map, GlobalState.selected_map)]
	info.add_theme_color_override("font_color", Color("#9eafd0"))
	box.add_child(info)
	floor_label = Label.new()
	floor_label.position = Vector2(1030, 22)
	floor_label.size = Vector2(220, 60)
	floor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	floor_label.add_theme_font_size_override("font_size", 22)
	floor_label.add_theme_color_override("font_color", Color("#ffd36e"))
	layer.add_child(floor_label)
	status = Label.new()
	status.position = Vector2(220, 650)
	status.size = Vector2(840, 36)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 18)
	layer.add_child(status)
	var hint := Label.new()
	hint.text = "WASD — ходьба   •   мышь — обзор   •   ЛКМ / ПРОБЕЛ — атака   •   P — пауза"
	hint.position = Vector2(0, 690)
	hint.size = Vector2(1280, 24)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("#9eafd0"))
	layer.add_child(hint)
	pause_panel = PanelContainer.new()
	pause_panel.position = Vector2(390, 245)
	pause_panel.size = Vector2(500, 190)
	pause_panel.visible = false
	pause_panel.add_theme_stylebox_override("panel", _style(Color("#0b1529f5"), Color("#64e8ff"), 2, 18))
	layer.add_child(pause_panel)
	var pause_box := VBoxContainer.new()
	pause_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pause_panel.add_child(pause_box)
	var title := Label.new()
	title.name = "Title"
	title.text = "ПАУЗА"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	pause_box.add_child(title)
	var pause_hint := Label.new()
	pause_hint.name = "Hint"
	pause_hint.text = "Нажми P, чтобы продолжить"
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_box.add_child(pause_hint)
	var menu_button := Button.new()
	menu_button.name = "ReturnMenu"
	menu_button.text = "В МЕНЮ"
	menu_button.visible = false
	menu_button.pressed.connect(_return_to_menu)
	pause_box.add_child(menu_button)

func _show_damage_vignette() -> void:
	if damage_overlay == null:
		return
	var tween := create_tween()
	damage_overlay.modulate.a = 0.0
	tween.tween_property(damage_overlay, "modulate:a", 1.0, 0.06)
	tween.tween_property(damage_overlay, "modulate:a", 0.0, 0.32)

func _update_hud() -> void:
	if hud == null:
		return
	var attack_damage: int = (3 if GlobalState.selected_class == "Knight" else 2) + GlobalState.get_stat(GlobalState.selected_class, "damage")
	hud.text = "♥ HP %d/%d     ⚔ УРОН %d     ☠ УБИЙСТВА %d" % [hp, max_hp, attack_damage, kills]
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	var room_index := clampi(int(round((35.0 - player.position.z) / ROOM_SPACING)), 0, ROOM_COUNT - 1)
	floor_label.text = "КОМНАТА %d / %d" % [room_index + 1, ROOM_COUNT]

func _set_end_panel(title_text: String, hint_text: String) -> void:
	var title := pause_panel.find_child("Title", true, false) as Label
	var hint := pause_panel.find_child("Hint", true, false) as Label
	if title != null:
		title.text = title_text
	if hint != null:
		hint.text = hint_text
	var menu_button := pause_panel.find_child("ReturnMenu", true, false) as Button
	if menu_button != null:
		menu_button.visible = true
	pause_panel.visible = true
	paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _return_to_menu() -> void:
	if pending_run_completion and not run_completed:
		GlobalState.complete_run(GlobalState.selected_class, GlobalState.selected_difficulty)
		run_completed = true
		pending_run_completion = false
	GlobalState.save_progress()
	get_tree().change_scene_to_file("res://menu/menu.tscn")

func _show_status(message: String, color: Color) -> void:
	if status == null:
		return
	status.text = message
	status.add_theme_color_override("font_color", color)
	if banner_tween and banner_tween.is_valid():
		banner_tween.kill()
	banner_tween = create_tween()
	banner_tween.tween_interval(2.0)
	banner_tween.tween_property(status, "modulate", Color(1, 1, 1, 0.35), 0.5)

func _style(color: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s
