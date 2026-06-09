extends RigidBody2D

func _ready() -> void:
	var mat := PhysicsMaterial.new()
	mat.bounce = 0.55
	mat.friction = 0.5
	physics_material_override = mat
