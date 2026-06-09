extends Node2D

var start_label: Label
var pulse_time := 0.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	Input.set_custom_mouse_cursor(
		load("res://assets/monkey_hand_cursor.png"),
		Input.CURSOR_ARROW,
		Vector2(30, 6)
	)

	var vp_size := get_viewport().get_visible_rect().size

	var bg := Sprite2D.new()
	bg.texture = load("res://assets/titlescreen.png")
	bg.position = vp_size * 0.5
	var tex_size := (bg.texture as Texture2D).get_size()
	var s: float = max(vp_size.x / tex_size.x, vp_size.y / tex_size.y)
	bg.scale = Vector2(s, s)
	add_child(bg)

	var canvas := CanvasLayer.new()
	add_child(canvas)

	start_label = Label.new()
	start_label.text = "— Click anywhere to start! —"
	start_label.add_theme_font_size_override("font_size", 40)
	start_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.15))
	start_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	start_label.add_theme_constant_override("shadow_offset_x", 3)
	start_label.add_theme_constant_override("shadow_offset_y", 3)
	start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_label.anchor_left   = 0.5
	start_label.anchor_right  = 0.5
	start_label.anchor_top    = 1.0
	start_label.anchor_bottom = 1.0
	start_label.offset_left   = -340
	start_label.offset_right  =  340
	start_label.offset_top    = -90
	start_label.offset_bottom = -30
	canvas.add_child(start_label)


func _process(delta: float) -> void:
	pulse_time += delta
	if start_label:
		start_label.modulate.a = 0.55 + 0.45 * sin(pulse_time * 2.8)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	elif event is InputEventKey and event.pressed:
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
