extends Control

# Aiming reticle. It's a plain crosshair drawn at its own origin; game_hud moves this
# Control to the projected on-screen aim point every frame. In most views that aim point
# is a WORLD point a fixed distance ahead of the ship along its fire line (-Z); in the
# angled 3-4 / isometric views it is RAY-TRACED along the shot path and lands directly on
# the enemy/mine in the line of fire, and the crosshair switches to its "locked" look.

@export var color: Color = Color(0.55, 1.0, 0.9, 0.85)
@export var locked_color: Color = Color(1.0, 0.45, 0.3, 0.95)   # sitting on an enemy/mine
@export var ring_radius: float = 11.0
@export var tick_gap: float = 4.0
@export var tick_len: float = 7.0
@export var line_width: float = 1.5

var locked: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = false

# Called by game_hud when the ray-traced aim is (or isn't) on a target.
func set_locked(value: bool) -> void:
	if value != locked:
		locked = value
		queue_redraw()

func _draw() -> void:
	var c: Color = locked_color if locked else color
	# Locked: draw a tighter inner ring + a faint fill so a target read is obvious.
	if locked:
		draw_circle(Vector2.ZERO, ring_radius * 0.5, Color(c.r, c.g, c.b, 0.18))
		draw_arc(Vector2.ZERO, ring_radius * 0.5, 0.0, TAU, 28, c, line_width, true)
	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 40, c, line_width, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		draw_line(d * (ring_radius + tick_gap), d * (ring_radius + tick_gap + tick_len), c, line_width, true)
	draw_circle(Vector2.ZERO, 1.5, c)
