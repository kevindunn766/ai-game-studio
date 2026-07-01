class_name TouchControls
extends CanvasLayer

signal move_left
signal move_right
signal jump
signal slide

var left_button: Button
var right_button: Button
var jump_button: Button
var slide_button: Button

func _ready() -> void:
    # Create touch buttons
    left_button = Button.new()
    left_button.text = "←"
    left_button.position = Vector2(20, 400)
    left_button.custom_minimum_size = Vector2(80, 80)
    left_button.pressed.connect(_on_left_pressed)
    add_child(left_button)

    right_button = Button.new()
    right_button.text = "→"
    right_button.position = Vector2(120, 400)
    right_button.custom_minimum_size = Vector2(80, 80)
    right_button.pressed.connect(_on_right_pressed)
    add_child(right_button)

    jump_button = Button.new()
    jump_button.text = "JUMP"
    jump_button.position = Vector2(1100, 400)
    jump_button.custom_minimum_size = Vector2(100, 80)
    jump_button.pressed.connect(_on_jump_pressed)
    add_child(jump_button)

    slide_button = Button.new()
    slide_button.text = "SLIDE"
    slide_button.position = Vector2(1220, 400)
    slide_button.custom_minimum_size = Vector2(100, 80)
    slide_button.pressed.connect(_on_slide_pressed)
    add_child(slide_button)

func _on_left_pressed() -> void:
    emit_signal("move_left")

func _on_right_pressed() -> void:
    emit_signal("move_right")

func _on_jump_pressed() -> void:
    emit_signal("jump")

func _on_slide_pressed() -> void:
    emit_signal("slide")
