extends Area3D
class_name RiftBolt

var direction: Vector3 = Vector3.FORWARD
var speed: float = 18.0
var damage: float = 20.0
var lifetime: float = 2.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 2
	monitoring = true
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	var collider := CollisionShape3D.new()
	collider.shape = sphere
	add_child(collider)

	var orb := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.17
	mesh.height = 0.34
	orb.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.46, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.08, 0.9, 1.0)
	material.emission_energy_multiplier = 3.0
	orb.material_override = material
	add_child(orb)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node3D) -> void:
	if body is RiftEnemy:
		body.take_damage(damage)
		queue_free()

