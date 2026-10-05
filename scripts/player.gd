extends CharacterBody3D
class_name RiftPlayer

var game: Node
var max_health: float = 100.0
var health: float = 100.0
var move_speed: float = 7.4
var shot_damage: float = 24.0
var fire_interval: float = 0.48
var fire_clock: float = 0.2
var dash_cooldown: float = 0.0
var invulnerable_time: float = 0.0
var dash_time: float = 0.0
var dash_direction: Vector3 = Vector3.FORWARD
var body_material: StandardMaterial3D

func _ready() -> void:
	name = "Player"
	collision_layer = 1
	collision_mask = 8
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.42
	capsule.height = 1.45
	collider.shape = capsule
	collider.position.y = 0.73
	add_child(collider)

	body_material = StandardMaterial3D.new()
	body_material.albedo_color = Color(0.14, 0.82, 1.0)
	body_material.emission_enabled = true
	body_material.emission = Color(0.02, 0.56, 1.0)
	body_material.emission_energy_multiplier = 1.4
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.4
	body_mesh.height = 1.35
	body.mesh = body_mesh
	body.material_override = body_material
	body.position.y = 0.72
	add_child(body)

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.16
	core_mesh.height = 0.32
	core.mesh = core_mesh
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color(0.8, 1.0, 1.0)
	core_material.emission_enabled = true
	core_material.emission = Color(0.12, 0.8, 1.0)
	core_material.emission_energy_multiplier = 2.0
	core.material_override = core_material
	core.position = Vector3(0, 1.13, -0.24)
	add_child(core)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.47
	ring_mesh.outer_radius = 0.52
	ring.mesh = ring_mesh
	ring.position.y = 0.08
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color(0.08, 0.75, 1.0, 0.72)
	ring_material.emission_enabled = true
	ring_material.emission = Color(0.02, 0.58, 1.0)
	ring_material.emission_energy_multiplier = 1.0
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_material
	add_child(ring)

func _physics_process(delta: float) -> void:
	fire_clock -= delta
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	invulnerable_time = maxf(0.0, invulnerable_time - delta)
	dash_time = maxf(0.0, dash_time - delta)

	var input_vector := game.get_move_input() if game != null else Vector2.ZERO
	if input_vector.length() < 0.08:
		input_vector = _keyboard_move()
	input_vector = input_vector.limit_length(1.0)
	var direction := Vector3(input_vector.x, 0.0, input_vector.y)

	if dash_time > 0.0:
		velocity.x = dash_direction.x * 19.0
		velocity.z = dash_direction.z * 19.0
	else:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	move_and_slide()
	global_position.x = clampf(global_position.x, -8.3, 8.3)
	global_position.z = clampf(global_position.z, -13.0, 13.0)

	if direction.length_squared() > 0.02 and dash_time <= 0.0:
		rotation.y = atan2(-direction.x, -direction.z)
	elif game != null:
		var target = game.get_nearest_enemy(global_position)
		if target != null:
			var toward := target.global_position - global_position
			rotation.y = atan2(-toward.x, -toward.z)

	if fire_clock <= 0.0 and game != null:
		var enemy = game.get_nearest_enemy(global_position, 12.0)
		if enemy != null:
			var aim := game.get_aim_direction()
			var shot_direction: Vector3
			if aim.length() > 0.2:
				shot_direction = Vector3(aim.x, 0.0, aim.y).normalized()
			else:
				shot_direction = (enemy.global_position - global_position).normalized()
			game.spawn_projectile(global_position + Vector3.UP * 0.78, shot_direction, shot_damage)
			fire_clock = fire_interval

	if invulnerable_time > 0.0:
		body_material.albedo_color = Color(0.7, 1.0, 1.0) if int(Time.get_ticks_msec() / 70) % 2 == 0 else Color(0.14, 0.82, 1.0)
	else:
		body_material.albedo_color = Color(0.14, 0.82, 1.0)

func _keyboard_move() -> Vector2:
	var result := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		result.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		result.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		result.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		result.y += 1.0
	return result.normalized()

func dash() -> void:
	if dash_cooldown > 0.0 or game == null or game.is_game_over:
		return
	var input_vector := game.get_move_input()
	if input_vector.length() < 0.08:
		input_vector = _keyboard_move()
	if input_vector.length() < 0.08:
		dash_direction = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	else:
		dash_direction = Vector3(input_vector.x, 0.0, input_vector.y).normalized()
	dash_time = 0.19
	dash_cooldown = 2.6
	invulnerable_time = maxf(invulnerable_time, 0.28)
	game.update_hud()

func take_damage(amount: float) -> void:
	if invulnerable_time > 0.0 or game.is_game_over:
		return
	health = maxf(0.0, health - amount)
	invulnerable_time = 0.48
	game.update_hud()
	if health <= 0.0:
		game.end_run()

func heal(amount: float) -> void:
	health = minf(max_health, health + amount)

