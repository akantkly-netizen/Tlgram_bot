extends Node3D

const PlayerScript = preload("res://scripts/player.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const BoltScript = preload("res://scripts/bolt.gd")

const ARENA_HALF_WIDTH := 8.7
const ARENA_HALF_DEPTH := 13.4

var player: RiftPlayer
var camera: Camera3D
var hud: CanvasLayer
var move_input := Vector2.ZERO
var aim_input := Vector2.ZERO
var move_touch_id := -1
var aim_touch_id := -1
var move_touch_origin := Vector2.ZERO
var aim_touch_origin := Vector2.ZERO
var joystick_knob: Control
var joystick_base: Control
var health_bar: ProgressBar
var wave_label: Label
var score_label: Label
var level_label: Label
var hint_label: Label
var dash_button: Button
var game_over_panel: PanelContainer
var game_over_label: Label
var wave := 1
var score := 0
var kills := 0
var level := 1
var xp := 0
var xp_next := 35
var spawn_remaining := 0
var spawn_clock := 0.0
var wave_pause := 0.0
var wave_active := false
var is_game_over := false
var upgrade_cycle := 0
var run_seconds := 0.0

func _ready() -> void:
	randomize()
	_build_world()
	_build_player()
	_build_camera()
	_build_hud()
	_start_wave()
	update_hud()

func _process(delta: float) -> void:
	if is_game_over:
		return
	run_seconds += delta
	if spawn_remaining > 0:
		spawn_clock -= delta
		if spawn_clock <= 0.0:
			_spawn_enemy()
			spawn_remaining -= 1
			spawn_clock = maxf(0.32, 0.86 - float(wave) * 0.035)
	elif wave_active and get_tree().get_nodes_in_group("enemies").is_empty():
		wave_active = false
		wave_pause = 2.2
		if hint_label != null:
			hint_label.text = "موج کامل شد • موج بعدی نزدیک است"
	elif not wave_active:
		wave_pause -= delta
		if wave_pause <= 0.0:
			wave += 1
			_start_wave()
	update_hud()

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.012, 0.018, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.19, 0.27, 0.43)
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.glow_enabled = true
	environment.glow_intensity = 0.65
	environment.glow_strength = 0.8
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color(0.52, 0.72, 1.0)
	sun.light_energy = 1.05
	add_child(sun)

	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(18.2, 27.4)
	floor.mesh = floor_mesh
	floor.position.y = -0.06
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.025, 0.045, 0.085)
	floor_material.roughness = 0.92
	floor.material_override = floor_material
	add_child(floor)

	var outline_material := StandardMaterial3D.new()
	outline_material.albedo_color = Color(0.04, 0.42, 0.8)
	outline_material.emission_enabled = true
	outline_material.emission = Color(0.015, 0.28, 0.85)
	outline_material.emission_energy_multiplier = 1.3
	_add_box(Vector3(17.5, 0.07, 0.075), Vector3(0.0, 0.025, -13.3), outline_material)
	_add_box(Vector3(17.5, 0.07, 0.075), Vector3(0.0, 0.025, 13.3), outline_material)
	_add_box(Vector3(0.075, 0.07, 26.7), Vector3(-8.75, 0.025, 0.0), outline_material)
	_add_box(Vector3(0.075, 0.07, 26.7), Vector3(8.75, 0.025, 0.0), outline_material)

	var grid_material := StandardMaterial3D.new()
	grid_material.albedo_color = Color(0.045, 0.09, 0.16)
	grid_material.emission_enabled = true
	grid_material.emission = Color(0.01, 0.09, 0.22)
	grid_material.emission_energy_multiplier = 0.42
	for x in range(-8, 9, 2):
		_add_box(Vector3(0.018, 0.012, 26.0), Vector3(float(x), 0.005, 0.0), grid_material)
	for z in range(-13, 14, 2):
		_add_box(Vector3(17.2, 0.012, 0.018), Vector3(0.0, 0.006, float(z)), grid_material)

	var pillar_material := StandardMaterial3D.new()
	pillar_material.albedo_color = Color(0.035, 0.12, 0.24)
	pillar_material.emission_enabled = true
	pillar_material.emission = Color(0.0, 0.2, 0.7)
	pillar_material.emission_energy_multiplier = 0.75
	var corners := [
		Vector3(-8.0, 0.8, -12.3), Vector3(8.0, 0.8, -12.3),
		Vector3(-8.0, 0.8, 12.3), Vector3(8.0, 0.8, 12.3)
	]
	for corner in corners:
		_add_cylinder(0.25, 1.6, corner, pillar_material)

	var obstacle_material := StandardMaterial3D.new()
	obstacle_material.albedo_color = Color(0.06, 0.12, 0.22)
	obstacle_material.emission_enabled = true
	obstacle_material.emission = Color(0.015, 0.16, 0.38)
	obstacle_material.emission_energy_multiplier = 0.38
	var obstacle_positions := [
		Vector3(-4.8, 0.45, -5.0), Vector3(4.8, 0.45, -5.0),
		Vector3(-4.8, 0.45, 5.0), Vector3(4.8, 0.45, 5.0),
		Vector3(0.0, 0.35, -8.5), Vector3(0.0, 0.35, 8.5)
	]
	for obstacle_position in obstacle_positions:
		_add_obstacle(obstacle_position, obstacle_material)

func _add_box(size: Vector3, at: Vector3, material: Material) -> void:
	var item := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	item.mesh = mesh
	item.material_override = material
	item.position = at
	add_child(item)

func _add_cylinder(radius: float, height: float, at: Vector3, material: Material) -> void:
	var item := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	item.mesh = mesh
	item.material_override = material
	item.position = at
	add_child(item)

func _add_obstacle(at: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 8
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.95, 0.9, 0.95)
	collider.shape = shape
	body.add_child(collider)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	add_child(body)

func _build_player() -> void:
	player = PlayerScript.new()
	player.game = self
	player.position = Vector3.ZERO
	add_child(player)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.position = Vector3(0.0, 20.5, 17.2)
	camera.fov = 48.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, -0.6), Vector3.UP)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 2
	add_child(hud)
	var root := Control.new()
	root.name = "HUD"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	var top_panel := PanelContainer.new()
	top_panel.anchor_left = 0.045
	top_panel.anchor_top = 0.025
	top_panel.anchor_right = 0.955
	top_panel.anchor_bottom = 0.13
	top_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.055, 0.11, 0.9), Color(0.06, 0.38, 0.7, 0.9), 18))
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_panel)

	var top_row := VBoxContainer.new()
	top_row.add_theme_constant_override("separation", 5)
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_panel.add_child(top_row)
	var title := _label("NEON RIFT", 20, Color(0.55, 0.92, 1.0))
	top_row.add_child(title)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 16)
	top_row.add_child(stats_row)
	wave_label = _label("موج ۱", 15, Color(1.0, 0.72, 0.27))
	score_label = _label("امتیاز ۰", 15, Color(0.84, 0.92, 1.0))
	level_label = _label("سطح ۱", 15, Color(0.4, 1.0, 0.78))
	stats_row.add_child(wave_label)
	stats_row.add_child(score_label)
	stats_row.add_child(level_label)

	var health_panel := PanelContainer.new()
	health_panel.anchor_left = 0.16
	health_panel.anchor_top = 0.145
	health_panel.anchor_right = 0.84
	health_panel.anchor_bottom = 0.187
	health_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.04, 0.08, 0.86), Color(0.1, 0.22, 0.4, 0.8), 12))
	health_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(health_panel)
	health_bar = ProgressBar.new()
	health_bar.min_value = 0
	health_bar.max_value = player.max_health
	health_bar.value = player.health
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(0, 15)
	var health_fill := StyleBoxFlat.new()
	health_fill.bg_color = Color(0.08, 0.93, 0.67)
	health_fill.corner_radius_top_left = 9
	health_fill.corner_radius_top_right = 9
	health_fill.corner_radius_bottom_left = 9
	health_fill.corner_radius_bottom_right = 9
	health_bar.add_theme_stylebox_override("fill", health_fill)
	var health_bg := StyleBoxFlat.new()
	health_bg.bg_color = Color(0.09, 0.15, 0.24)
	health_bg.corner_radius_top_left = 9
	health_bg.corner_radius_top_right = 9
	health_bg.corner_radius_bottom_left = 9
	health_bg.corner_radius_bottom_right = 9
	health_bar.add_theme_stylebox_override("background", health_bg)
	health_panel.add_child(health_bar)

	hint_label = _label("حرکت کن و زنده بمان", 15, Color(0.64, 0.82, 1.0))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.anchor_left = 0.18
	hint_label.anchor_top = 0.205
	hint_label.anchor_right = 0.82
	hint_label.anchor_bottom = 0.25
	root.add_child(hint_label)

	joystick_base = Panel.new()
	joystick_base.anchor_left = 0.055
	joystick_base.anchor_top = 0.75
	joystick_base.anchor_right = 0.31
	joystick_base.anchor_bottom = 0.92
	joystick_base.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.16, 0.26, 0.48), Color(0.24, 0.71, 0.95, 0.68), 100))
	joystick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(joystick_base)
	joystick_knob = Panel.new()
	joystick_knob.anchor_left = 0.29
	joystick_knob.anchor_top = 0.24
	joystick_knob.anchor_right = 0.71
	joystick_knob.anchor_bottom = 0.66
	joystick_knob.add_theme_stylebox_override("panel", _panel_style(Color(0.24, 0.75, 1.0, 0.8), Color(0.64, 0.96, 1.0, 0.95), 100))
	joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	joystick_base.add_child(joystick_knob)

	var move_hint := _label("حرکت", 13, Color(0.67, 0.88, 1.0, 0.85))
	move_hint.anchor_left = 0.055
	move_hint.anchor_top = 0.925
	move_hint.anchor_right = 0.31
	move_hint.anchor_bottom = 0.96
	move_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(move_hint)

	dash_button = Button.new()
	dash_button.text = "جهش"
	dash_button.anchor_left = 0.75
	dash_button.anchor_top = 0.765
	dash_button.anchor_right = 0.95
	dash_button.anchor_bottom = 0.89
	dash_button.add_theme_font_size_override("font_size", 20)
	dash_button.add_theme_color_override("font_color", Color(0.92, 1.0, 1.0))
	dash_button.add_theme_stylebox_override("normal", _panel_style(Color(0.06, 0.32, 0.49, 0.86), Color(0.15, 0.8, 1.0), 100))
	dash_button.add_theme_stylebox_override("pressed", _panel_style(Color(0.12, 0.6, 0.8, 0.96), Color(0.6, 0.98, 1.0), 100))
	dash_button.add_theme_stylebox_override("hover", _panel_style(Color(0.1, 0.43, 0.62, 0.92), Color(0.4, 0.9, 1.0), 100))
	dash_button.pressed.connect(_on_dash_pressed)
	root.add_child(dash_button)

	var aim_hint := _label("لمس و کشیدن برای هدف‌گیری", 12, Color(0.5, 0.77, 0.9, 0.8))
	aim_hint.anchor_left = 0.62
	aim_hint.anchor_top = 0.91
	aim_hint.anchor_right = 0.98
	aim_hint.anchor_bottom = 0.95
	aim_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(aim_hint)

	game_over_panel = PanelContainer.new()
	game_over_panel.anchor_left = 0.12
	game_over_panel.anchor_top = 0.34
	game_over_panel.anchor_right = 0.88
	game_over_panel.anchor_bottom = 0.65
	game_over_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.035, 0.08, 0.96), Color(0.17, 0.62, 0.94), 24))
	game_over_panel.visible = false
	root.add_child(game_over_panel)
	var over_box := VBoxContainer.new()
	over_box.alignment = BoxContainer.ALIGNMENT_CENTER
	over_box.add_theme_constant_override("separation", 17)
	game_over_panel.add_child(over_box)
	game_over_label = _label("پایان بازی", 26, Color(1.0, 0.45, 0.55))
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_box.add_child(game_over_label)
	var final_score := _label("", 18, Color(0.8, 0.9, 1.0))
	final_score.name = "FinalScore"
	final_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_box.add_child(final_score)
	var retry_button := Button.new()
	retry_button.text = "تلاش دوباره"
	retry_button.custom_minimum_size = Vector2(0, 58)
	retry_button.add_theme_font_size_override("font_size", 19)
	retry_button.add_theme_stylebox_override("normal", _panel_style(Color(0.02, 0.5, 0.52), Color(0.12, 1.0, 0.8), 14))
	retry_button.add_theme_stylebox_override("pressed", _panel_style(Color(0.02, 0.72, 0.62), Color(0.6, 1.0, 0.85), 14))
	retry_button.pressed.connect(_restart)
	over_box.add_child(retry_button)

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _start_wave() -> void:
	wave_active = true
	spawn_remaining = 5 + wave * 2
	spawn_clock = 0.5
	if hint_label != null:
		hint_label.text = "موج %d • آماده باش" % wave

func _spawn_enemy() -> void:
	var enemy: RiftEnemy = EnemyScript.new()
	enemy.game = self
	enemy.is_elite = wave % 5 == 0 and spawn_remaining == 1
	enemy.health = (48.0 + float(wave - 1) * 8.0) * (2.8 if enemy.is_elite else 1.0)
	enemy.move_speed = minf(4.4, 2.75 + float(wave - 1) * 0.07) * (0.78 if enemy.is_elite else 1.0)
	enemy.touch_damage = (11.0 + float(wave - 1) * 1.4) * (1.5 if enemy.is_elite else 1.0)
	var angle := randf_range(0.0, TAU)
	var edge := randf_range(0.0, 1.0)
	if edge < 0.5:
		enemy.position = Vector3(cos(angle) * 7.8, 0.0, signf(sin(angle)) * randf_range(9.5, 12.1))
	else:
		enemy.position = Vector3(signf(cos(angle)) * randf_range(6.3, 8.0), 0.0, sin(angle) * 11.8)
	add_child(enemy)
	if enemy.is_elite:
		hint_label.text = "خطر • دشمن نخبۀ موج %d" % wave

func get_nearest_enemy(from_position: Vector3, max_distance: float = 1000.0) -> RiftEnemy:
	var nearest: RiftEnemy = null
	var nearest_distance := max_distance
	for node in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(node):
			continue
		var enemy := node as RiftEnemy
		var distance := from_position.distance_to(enemy.global_position)
		if distance < nearest_distance:
			nearest = enemy
			nearest_distance = distance
	return nearest

func spawn_projectile(at: Vector3, direction: Vector3, damage: float) -> void:
	var bolt: RiftBolt = BoltScript.new()
	bolt.direction = direction.normalized()
	bolt.damage = damage
	bolt.position = at
	add_child(bolt)

func enemy_killed(enemy: RiftEnemy) -> void:
	kills += 1
	score += 100 if enemy.is_elite else 25
	xp += 12 if enemy.is_elite else 8
	if enemy.is_elite:
		player.heal(18.0)
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = int(float(xp_next) * 1.28) + 8
		_apply_upgrade()
		if hint_label != null:
			hint_label.text = "ارتقا! سطح %d" % level
	update_hud()

func _apply_upgrade() -> void:
	upgrade_cycle = (upgrade_cycle + 1) % 3
	match upgrade_cycle:
		0:
			player.shot_damage += 6.0
		1:
			player.fire_interval = maxf(0.22, player.fire_interval * 0.9)
		2:
			player.max_health += 12.0
			player.health = minf(player.max_health, player.health + 24.0)
			health_bar.max_value = player.max_health

func update_hud() -> void:
	if hud == null or player == null:
		return
	wave_label.text = "موج %d" % wave
	score_label.text = "امتیاز %d" % score
	level_label.text = "سطح %d  •  XP %d/%d" % [level, xp, xp_next]
	health_bar.max_value = player.max_health
	health_bar.value = player.health
	if dash_button != null:
		dash_button.disabled = player.dash_cooldown > 0.0

func get_move_input() -> Vector2:
	return move_input

func get_aim_direction() -> Vector2:
	return aim_input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if player != null:
			player.dash()
	elif event is InputEventScreenTouch:
		var screen_size := get_viewport().get_visible_rect().size
		if event.pressed:
			if event.position.y > screen_size.y * 0.48 and event.position.x < screen_size.x * 0.48 and move_touch_id == -1:
				move_touch_id = event.index
				move_touch_origin = event.position
				_update_move_from_touch(event.position)
			elif event.position.y > screen_size.y * 0.48 and aim_touch_id == -1:
				aim_touch_id = event.index
				aim_touch_origin = event.position
				aim_input = Vector2.ZERO
		else:
			if event.index == move_touch_id:
				move_touch_id = -1
				move_input = Vector2.ZERO
				_reset_joystick()
			if event.index == aim_touch_id:
				aim_touch_id = -1
				aim_input = Vector2.ZERO
	elif event is InputEventScreenDrag:
		if event.index == move_touch_id:
			_update_move_from_touch(event.position)
		elif event.index == aim_touch_id:
			var drag := event.position - aim_touch_origin
			if drag.length() > 22.0:
				aim_input = drag.normalized()

func _update_move_from_touch(position: Vector2) -> void:
	var base_center := joystick_base.global_position + joystick_base.size * 0.5
	var offset := position - move_touch_origin
	if (position - move_touch_origin).length() < 10.0:
		offset = position - base_center
	var radius := maxf(38.0, minf(joystick_base.size.x, joystick_base.size.y) * 0.39)
	move_input = (offset / radius).limit_length(1.0)
	if joystick_knob != null:
		var normalized_offset := move_input * 0.23
		joystick_knob.anchor_left = 0.29 + normalized_offset.x
		joystick_knob.anchor_right = 0.71 + normalized_offset.x
		joystick_knob.anchor_top = 0.24 + normalized_offset.y
		joystick_knob.anchor_bottom = 0.66 + normalized_offset.y

func _reset_joystick() -> void:
	if joystick_knob == null:
		return
	joystick_knob.anchor_left = 0.29
	joystick_knob.anchor_right = 0.71
	joystick_knob.anchor_top = 0.24
	joystick_knob.anchor_bottom = 0.66

func _on_dash_pressed() -> void:
	if player != null:
		player.dash()

func end_run() -> void:
	is_game_over = true
	game_over_panel.visible = true
	game_over_label.text = "پایان بازی"
	var final_label := game_over_panel.find_child("FinalScore", true, false) as Label
	if final_label != null:
		final_label.text = "امتیاز %d  •  موج %d  •  حذف %d" % [score, wave, kills]
	hint_label.text = "این بار تا موج %d دوام آوردی" % wave

func _restart() -> void:
	get_tree().reload_current_scene()

