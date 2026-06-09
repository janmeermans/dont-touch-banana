extends Node2D

# ── Tuning ────────────────────────────────────────────────────────────────────
const BOX_HALF        := 150.0
const WALL_T          := 40.0
const CIRCLE_RADIUS   := 10.0
const CIRCLE_SCORE    := 50
const INITIAL_CIRCLES := 3
const BASE_SPEED      := 0.4   # rad/s when box first starts spinning
const SPEED_STEP      := 0.25  # rad/s gained per collected circle

const ROPE_LINKS    := 5
const ROPE_SPACING  := 16.0    # px between link centres
const BANANA_ATTACH := 44.0    # banana-local y of the rope connection point

# ── State ─────────────────────────────────────────────────────────────────────
var score            : int    = 0
var rotation_speed   : float  = BASE_SPEED
var rotation_started : bool   = false
var is_playing       : bool   = true
var box_rotation     : float  = 0.0
var box_center       : Vector2 = Vector2.ZERO

# ── Nodes ─────────────────────────────────────────────────────────────────────
var box_body   : AnimatableBody2D
var box_visual : Node2D
var cursor_node: Node2D
var cursor_area: Area2D
var score_label      : Label
var final_score_label: Label
var game_over_panel  : Control
var bananas: Array[RigidBody2D] = []
var circles: Array[RigidBody2D] = []

# ── Rope ──────────────────────────────────────────────────────────────────────
var rope_anchor      : AnimatableBody2D  # tracks the rotating corner each physics tick
var rope_anchor_local: Vector2 = Vector2.ZERO
var rope_links : Array[RigidBody2D] = []
var rope_joints: Array[Joint2D]     = []
var rope_visual: Line2D


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	Engine.physics_ticks_per_second = 120  # halves per-tick wall movement, prevents tunneling
	var vp := get_viewport().get_visible_rect().size
	box_center   = vp * 0.5
	box_rotation = PI / 4.0  # diamond orientation — top corner pointing up
	_create_background(vp)
	_create_ui()
	_create_box(box_center)
	_spawn_banana_on_rope()
	for _i in INITIAL_CIRCLES:
		_spawn_circle()
	_setup_cursor()


func _physics_process(delta: float) -> void:
	if is_playing and rotation_started:
		box_rotation      += rotation_speed * delta
		box_body.rotation  = box_rotation
	if rope_anchor != null and is_instance_valid(rope_anchor):
		rope_anchor.position = box_center + rope_anchor_local.rotated(box_rotation)


func _process(_delta: float) -> void:
	box_visual.rotation = box_rotation
	if cursor_node:
		cursor_node.position = get_global_mouse_position()
	_update_rope_visual()
	if not is_playing:
		return
	score_label.text = "Score: %d" % score
	if cursor_area:
		_check_cursor_overlaps()


func _input(event: InputEvent) -> void:
	if is_playing:
		return
	var restart := event is InputEventMouseButton \
				or (event is InputEventKey and (event as InputEventKey).keycode == KEY_SPACE)
	if restart and event.is_pressed():
		get_tree().reload_current_scene()


# ── Setup ─────────────────────────────────────────────────────────────────────

func _setup_cursor() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	var scene := load("res://scenes/Cursor.tscn") as PackedScene
	cursor_node = scene.instantiate() as Node2D
	cursor_node.position = get_global_mouse_position()
	add_child(cursor_node)
	cursor_area = cursor_node.get_node("Area2D") as Area2D


func _create_background(vp: Vector2) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.05, 0.10)
	bg.size  = vp
	add_child(bg)


func _create_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	score_label = Label.new()
	score_label.position = Vector2(20, 20)
	score_label.add_theme_font_size_override("font_size", 36)
	score_label.modulate = Color(1.0, 0.9, 0.1)
	score_label.text = "Score: 0"
	canvas.add_child(score_label)

	# Game-over overlay — fullscreen image with score and restart prompt on top
	game_over_panel = TextureRect.new()
	(game_over_panel as TextureRect).texture      = load("res://assets/you_failed.png")
	(game_over_panel as TextureRect).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	game_over_panel.anchor_right  = 1.0
	game_over_panel.anchor_bottom = 1.0
	game_over_panel.visible = false
	canvas.add_child(game_over_panel)

	final_score_label = _make_label("", 42, Color(1.0, 0.95, 0.15), 3)
	_anchor_centered(final_score_label, -300, 300, -110, -55)
	game_over_panel.add_child(final_score_label)

	var restart := _make_label("Click or press SPACE to try again", 24, Color(1.0, 1.0, 1.0), 2)
	_anchor_centered(restart, -300, 300, -45, 5)
	game_over_panel.add_child(restart)


func _create_box(center: Vector2) -> void:
	box_body = AnimatableBody2D.new()
	box_body.position        = center
	box_body.rotation        = box_rotation
	box_body.sync_to_physics = false
	add_child(box_body)

	box_visual = Node2D.new()
	box_visual.position = center
	box_visual.rotation = box_rotation
	add_child(box_visual)

	var h := BOX_HALF
	var t := WALL_T
	var wall_defs: Array = [
		[Vector2(0,             -(h + t * 0.5)), Vector2(h * 2 + t * 2, t)],
		[Vector2(0,              (h + t * 0.5)), Vector2(h * 2 + t * 2, t)],
		[Vector2(-(h + t * 0.5), 0),             Vector2(t, (h + t) * 2)],
		[Vector2( (h + t * 0.5), 0),             Vector2(t, (h + t) * 2)],
	]
	for wd: Array in wall_defs:
		var offset: Vector2 = wd[0]
		var size: Vector2   = wd[1]
		_add_wall_physics(offset, size)
		_add_wall_visual(offset, size)

	var edge := Line2D.new()
	edge.default_color = Color(1.0, 0.85, 0.3)
	edge.width         = 3.0
	edge.joint_mode    = Line2D.LINE_JOINT_SHARP
	edge.points = PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h), Vector2(-h, -h),
	])
	box_visual.add_child(edge)

	# Rope anchor nail — top-left local corner = top of the diamond at 45°
	var nail_pos := Vector2(-h + 5.0, -h + 5.0)
	var nail     := Polygon2D.new()
	nail.color = Color(0.85, 0.75, 0.5)
	var nail_pts := PackedVector2Array()
	for i: int in range(10):
		var a := TAU * float(i) / 10.0
		nail_pts.append(nail_pos + Vector2(cos(a), sin(a)) * 5.0)
	nail.polygon = nail_pts
	box_visual.add_child(nail)


func _add_wall_physics(offset: Vector2, size: Vector2) -> void:
	var cs   := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size   = size
	cs.position = offset
	cs.shape    = rect
	box_body.add_child(cs)


func _add_wall_visual(offset: Vector2, size: Vector2) -> void:
	var hw   := size.x * 0.5
	var hh   := size.y * 0.5
	var poly := Polygon2D.new()
	poly.color = Color(0.55, 0.42, 0.12, 0.85)
	poly.polygon = PackedVector2Array([
		offset + Vector2(-hw, -hh), offset + Vector2(hw, -hh),
		offset + Vector2(hw,   hh), offset + Vector2(-hw,  hh),
	])
	box_visual.add_child(poly)


# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_banana_on_rope() -> void:
	# (-BOX_HALF, -BOX_HALF) in local space maps to the top of the diamond at 45° rotation.
	rope_anchor_local = Vector2(-BOX_HALF + 5.0, -BOX_HALF + 5.0)
	var anchor_world  := box_center + rope_anchor_local.rotated(box_rotation)

	rope_anchor = AnimatableBody2D.new()
	rope_anchor.position        = anchor_world
	rope_anchor.sync_to_physics = false
	rope_anchor.collision_layer = 0
	rope_anchor.collision_mask  = 0
	var acs := CollisionShape2D.new()
	var ash := CircleShape2D.new()
	ash.radius = 2.0
	acs.shape  = ash
	rope_anchor.add_child(acs)
	add_child(rope_anchor)

	for i: int in range(ROPE_LINKS):
		var link := RigidBody2D.new()
		link.position        = anchor_world + Vector2(0.0, (float(i) + 0.5) * ROPE_SPACING)
		link.gravity_scale   = 0.4
		link.linear_damp     = 0.6
		link.collision_layer = 0
		link.collision_mask  = 0
		var cs := CollisionShape2D.new()
		var sh := CircleShape2D.new()
		sh.radius = 3.0
		cs.shape  = sh
		link.add_child(cs)
		add_child(link)
		rope_links.append(link)

	var banana := (load("res://scenes/Banana.tscn") as PackedScene).instantiate() as RigidBody2D
	banana.position = anchor_world + Vector2(0.0, float(ROPE_LINKS) * ROPE_SPACING + BANANA_ATTACH)
	add_child(banana)
	bananas.append(banana)

	# Joints added after all bodies are in the tree so NodePaths resolve correctly.
	_pin(anchor_world,                                                rope_anchor,              rope_links[0])
	for i: int in range(ROPE_LINKS - 1):
		_pin(anchor_world + Vector2(0.0, float(i + 1) * ROPE_SPACING), rope_links[i],          rope_links[i + 1])
	_pin(banana.position + Vector2(0.0, -BANANA_ATTACH),              rope_links[ROPE_LINKS - 1], banana)

	rope_visual = Line2D.new()
	rope_visual.default_color = Color(0.40, 0.25, 0.08)
	rope_visual.width   = 4.0
	rope_visual.z_index = 5
	add_child(rope_visual)


func _pin(world_pos: Vector2, a: PhysicsBody2D, b: PhysicsBody2D) -> void:
	var j  := PinJoint2D.new()
	j.position = world_pos
	j.node_a   = a.get_path()
	j.node_b   = b.get_path()
	add_child(j)
	rope_joints.append(j)


func _spawn_banana() -> void:
	var b := (load("res://scenes/Banana.tscn") as PackedScene).instantiate() as RigidBody2D
	b.position = box_center + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
	add_child(b)
	bananas.append(b)


func _spawn_circle() -> void:
	var body := RigidBody2D.new()
	body.position      = box_center + Vector2(randf_range(-30.0, 30.0), randf_range(-30.0, 30.0))
	body.gravity_scale = 1.2
	body.linear_damp   = 0.1
	var mat := PhysicsMaterial.new()
	mat.bounce   = 0.75
	mat.friction = 0.2
	body.physics_material_override = mat

	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = CIRCLE_RADIUS
	cs.shape  = sh
	body.add_child(cs)
	body.add_child(_circle_polygon(CIRCLE_RADIUS,        20, Color(0.15, 0.90, 0.30, 1.00)))
	body.add_child(_circle_polygon(CIRCLE_RADIUS * 0.45, 12, Color(0.60, 1.00, 0.65, 0.70)))
	add_child(body)
	circles.append(body)


func _circle_polygon(radius: float, steps: int, color: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.color = color
	var pts  := PackedVector2Array()
	for i: int in range(steps):
		var a := TAU * float(i) / float(steps)
		pts.append(Vector2(cos(a), sin(a)) * radius)
	poly.polygon = pts
	return poly


# ── Game loop ─────────────────────────────────────────────────────────────────

func _check_cursor_overlaps() -> void:
	for body: PhysicsBody2D in cursor_area.get_overlapping_bodies():
		if bananas.has(body):
			_game_over()
			return
		if body is RigidBody2D:
			var idx: int = circles.find(body as RigidBody2D)
			if idx >= 0:
				_collect_circle(idx)
				return


func _update_rope_visual() -> void:
	if rope_visual == null or not is_instance_valid(rope_visual):
		return
	var pts := PackedVector2Array()
	pts.append(box_center + rope_anchor_local.rotated(box_rotation))
	for link: RigidBody2D in rope_links:
		pts.append(link.global_position)
	if bananas.size() > 0 and is_instance_valid(bananas[0]):
		pts.append(bananas[0].to_global(Vector2(0.0, -BANANA_ATTACH)))
	rope_visual.points = pts


func _collect_circle(index: int) -> void:
	circles[index].queue_free()
	circles.remove_at(index)
	score += CIRCLE_SCORE
	if not rotation_started:
		rotation_started = true
		rotation_speed   = BASE_SPEED
	else:
		rotation_speed += SPEED_STEP
	_spawn_banana()
	_spawn_circle()


func _game_over() -> void:
	is_playing = false
	for b: RigidBody2D in bananas:
		b.freeze = true
	for l: RigidBody2D in rope_links:
		if is_instance_valid(l):
			l.freeze = true
	final_score_label.text = "Final Score: %d" % score
	game_over_panel.visible = true


# ── UI helpers ────────────────────────────────────────────────────────────────

func _make_label(text: String, font_size: int, color: Color, shadow: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 1.0))
	lbl.add_theme_constant_override("shadow_offset_x", shadow)
	lbl.add_theme_constant_override("shadow_offset_y", shadow)
	return lbl


func _anchor_centered(node: Control, l: float, r: float, t: float, b: float) -> void:
	node.anchor_left   = 0.5
	node.anchor_right  = 0.5
	node.anchor_top    = 0.5
	node.anchor_bottom = 0.5
	node.offset_left   = l
	node.offset_right  = r
	node.offset_top    = t
	node.offset_bottom = b
