extends CharacterBody3D
class_name RiftEnemy

var game: Node
var health: float = 48.0
var move_speed: float = 2.8
var touch_damage: float = 11.0
var attack_clock: float = 0.0
var is_elite: bool = false
var dead: bool = false

func _ready() -> void:
	name = "Enemy"
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 8
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4 if not is_elite else 0.61
	capsule.height = 1.15 if not is_elite else 1.75
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	add_child(collider)

	var shell := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = capsule.radius
	mesh.height = capsule.height
	shell.mesh = mesh
	shell.position.y = capsule.height * 0.5
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.18, 0.42) if not is_elite else Color(1.0, 0.48, 0.08)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.035, 0.22) if not is_elite else Color(1.0, 0.2, 0.01)
	material.emission_energy_multiplier = 1.25 if not is_elite else 1.8
	shell.material_override = material
	add_child(shell)

	var eye := MeshInstance3D.new()
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.1 if not is_elite else 0.14
	eye_mesh.height = eye_mesh.radius * 2.0
	eye.mesh = eye_mesh
	eye.position = Vector3(0.0, capsule.height * 0.68, -capsule.radius * 0.85)
	var eye_material := StandardMaterial3D.new()
	eye_material.albedo_color = Color(1.0, 0.95, 0.56)
	eye_material.emission_enabled = true
	eye_material.emission = Color(1.0, 0.4, 0.08)
	eye_material.emission_energy_multiplier = 2.2
	eye.material_override = eye_material
	add_child(eye)

func _physics_process(delta: float) -> void:
	if dead or game == null or game.player == null or game.is_game_over:
		return
	attack_clock = maxf(0.0, attack_clock - delta)
	var difference: Vector3 = game.player.global_position - global_position
	difference.y = 0.0
	var distance := difference.length()
	if distance > 1.12:
		var direction := difference.normalized()
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
		move_and_slide()
		global_position.x = clampf(global_position.x, -8.0, 8.0)
		global_position.z = clampf(global_position.z, -12.7, 12.7)
		rotation.y = atan2(-direction.x, -direction.z)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		if attack_clock <= 0.0:
			game.player.take_damage(touch_damage)
			attack_clock = 0.86

func take_damage(amount: float) -> void:
	if dead:
		return
	health -= amount
	if health <= 0.0:
		dead = true
		game.enemy_killed(self)
		queue_free()

