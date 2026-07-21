extends Node
# Root controller for the Shatter Duel prototype.
# Builds the 3D world + UI in code (grey-box), wires the lobby, and runs the
# real-time break/garbage/win loop on top of the Net autoload.
#
# Core rule (confirmed with Kevin): break blocks on YOUR board to clear it;
# every block you break lands on the OPPONENT'S board. First board to reach
# zero wins. Both boards stay in sync over the wireless link.
#
# Headless self-test:
#   godot --headless --path . -- --server --selftest
#   godot --headless --path . -- --client --selftest
# Each side auto-breaks a block every tick; verifies the net loop and win end
# state without any rendering or touch input.

const BoardScript := preload("res://scripts/board.gd")

const START_BLOCKS := 15

var _world: Node3D
var _local_board: Node3D
var _opp_board: Node3D
var _status: Label
var _hud: Label
var _result: Label
var _lobby: Control
var _ip_edit: LineEdit

var _selftest := false
var _role := "?"
var _game_over := false

func _ready() -> void:
	_build_world()
	_build_ui()

	Net.peer_ready.connect(_on_peer_ready)
	Net.opponent_left.connect(_on_opponent_left)
	Net.status_changed.connect(_set_status)
	Net.garbage_received.connect(_on_garbage_received)
	Net.opponent_count_changed.connect(_on_opponent_count_changed)
	Net.opponent_declared_win.connect(_on_opponent_declared_win)

	var uargs := OS.get_cmdline_user_args()
	_selftest = uargs.has("--selftest")
	if uargs.has("--server"):
		_role = "HOST"
		_lobby.visible = false
		Net.host_game()
	elif uargs.has("--client"):
		_role = "CLIENT"
		_lobby.visible = false
		Net.join_ip("127.0.0.1")

# ---------------------------------------------------------------- world / UI
func _build_world() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	var camera := Camera3D.new()
	camera.look_at_from_position(Vector3(0.0, 3.2, 9.0), Vector3(0.0, 1.6, 0.0), Vector3.UP)
	_world.add_child(camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	_world.add_child(light)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("11141c")
	e.ambient_light_color = Color("404650")
	e.ambient_light_energy = 1.0
	env.environment = e
	_world.add_child(env)

	_local_board = BoardScript.new()
	_local_board.interactive = true
	_local_board.position = Vector3(-2.4, 0.4, 0.0)
	_local_board.block_tapped.connect(_on_local_block_tapped)
	_world.add_child(_local_board)

	_opp_board = BoardScript.new()
	_opp_board.interactive = false
	_opp_board.position = Vector3(2.4, 0.4, 0.0)
	_world.add_child(_opp_board)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_lobby = Control.new()
	_lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_lobby)

	var vb := VBoxContainer.new()
	vb.position = Vector2(40.0, 70.0)
	vb.custom_minimum_size = Vector2(360.0, 0.0)
	_lobby.add_child(vb)

	var title := Label.new()
	title.text = "SHATTER DUEL - prototype"
	vb.add_child(title)

	var host_btn := Button.new()
	host_btn.text = "HOST  (turn on this phone's hotspot first)"
	host_btn.pressed.connect(_on_host_pressed)
	vb.add_child(host_btn)

	var join_btn := Button.new()
	join_btn.text = "JOIN  (auto-find host on this network)"
	join_btn.pressed.connect(_on_join_auto_pressed)
	vb.add_child(join_btn)

	_ip_edit = LineEdit.new()
	_ip_edit.placeholder_text = "or type host IP (e.g. 192.168.43.1)"
	vb.add_child(_ip_edit)

	var join_ip_btn := Button.new()
	join_ip_btn.text = "JOIN BY IP"
	join_ip_btn.pressed.connect(_on_join_ip_pressed)
	vb.add_child(join_ip_btn)

	_status = Label.new()
	_status.position = Vector2(40.0, 24.0)
	layer.add_child(_status)

	_hud = Label.new()
	_hud.position = Vector2(40.0, 360.0)
	layer.add_child(_hud)

	_result = Label.new()
	_result.set_anchors_preset(Control.PRESET_CENTER)
	_result.add_theme_font_size_override("font_size", 56)
	_result.visible = false
	layer.add_child(_result)

# ---------------------------------------------------------------- lobby input
func _on_host_pressed() -> void:
	_role = "HOST"
	_lobby.visible = false
	Net.host_game()

func _on_join_auto_pressed() -> void:
	_role = "CLIENT"
	_lobby.visible = false
	Net.join_auto()

func _on_join_ip_pressed() -> void:
	_role = "CLIENT"
	_lobby.visible = false
	Net.join_ip(_ip_edit.text)

# ---------------------------------------------------------------- match flow
func _on_peer_ready() -> void:
	_set_status("Connected as %s" % _role)
	_game_over = false
	_local_board.fill(START_BLOCKS)
	_opp_board.set_count(START_BLOCKS)
	_update_hud()
	Net.send_count(_local_board.count())
	if _selftest:
		_start_selftest()

func _on_opponent_left() -> void:
	if _game_over:
		return
	_set_status("Opponent disconnected")

func _on_local_block_tapped(body: Node3D) -> void:
	if _game_over:
		return
	_shoot_at(body)

# A quick projectile from the cannon to the block, then the break resolves.
func _shoot_at(body: Node3D) -> void:
	var proj := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	proj.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffffff")
	mat.emission_enabled = true
	mat.emission = Color("ffe08a")
	proj.material_override = mat
	proj.global_position = _local_board.to_global(Vector3(0.0, -0.7, 0.6))
	_world.add_child(proj)

	var tw := create_tween()
	tw.tween_property(proj, "global_position", body.global_position, 0.12)
	tw.tween_callback(_finish_shot.bind(proj, body))

func _finish_shot(proj: Node3D, body: Node3D) -> void:
	if is_instance_valid(proj):
		proj.queue_free()
	_do_break(body)

# The one place a local block is destroyed -> garbage to opponent -> win check.
func _do_break(body: Node3D) -> void:
	if _game_over or not is_instance_valid(body):
		return
	if not _local_board.has_block(body):
		return
	_local_board.remove_one(body)
	Net.send_garbage(1)
	_after_local_change()

func _after_local_change() -> void:
	_update_hud()
	Net.send_count(_local_board.count())
	if _local_board.count() == 0 and not _game_over:
		_game_over = true
		Net.send_win()
		_show_result("YOU WIN!")

# ---------------------------------------------------------------- net -> local
func _on_garbage_received(count: int) -> void:
	if _game_over:
		return
	_local_board.add_blocks(count)
	_after_local_change()

func _on_opponent_count_changed(n: int) -> void:
	_opp_board.set_count(n)
	_update_hud()

func _on_opponent_declared_win() -> void:
	if _game_over:
		return
	_game_over = true
	_show_result("YOU LOSE")

# ---------------------------------------------------------------- ui helpers
func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text

func _update_hud() -> void:
	if _hud != null:
		_hud.text = "You: %d blocks    Opponent: %d blocks" % [_local_board.count(), _opp_board.count()]

func _show_result(text: String) -> void:
	_result.text = text
	_result.visible = true
	_set_status(text)
	if _selftest:
		print("[selftest] %s RESULT %s (mine=%d opp=%d)" % [_role, text, _local_board.count(), _opp_board.count()])
		get_tree().create_timer(1.0).timeout.connect(_quit)

# ---------------------------------------------------------------- self-test
func _start_selftest() -> void:
	var t := Timer.new()
	t.wait_time = 0.35
	t.autostart = true
	t.timeout.connect(_selftest_tick)
	add_child(t)
	# Headless quit guard: never let a stuck run hang the session.
	get_tree().create_timer(25.0).timeout.connect(_quit)

func _selftest_tick() -> void:
	if _game_over:
		return
	var b: Node3D = _local_board.any_block()
	if b != null:
		_do_break(b)
	print("[selftest] %s mine=%d opp=%d" % [_role, _local_board.count(), _opp_board.count()])

func _quit() -> void:
	get_tree().quit()
