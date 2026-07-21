extends RefCounted

# Lays out a formation of mines around a navigable center point, in the plane
# facing the player (XY, at the center's z). Patterns, per Kevin: lines that are
# vertical, horizontal, or diagonal, or a shape like a ring or diamond. Each mine's
# chain radius is set to just over the formation spacing, so detonating one ripples
# along the formation (shoot one in a ring -> the whole ring goes).

const MINE := preload("res://scripts/mine.gd")

const PATTERNS := ["line_v", "line_h", "line_d", "ring", "diamond"]

static func build(center: Vector3, scale: float, theme: Dictionary, ship: Node3D, world: Node3D, rng: RandomNumberGenerator) -> Array:
	var pattern: String = PATTERNS[rng.randi_range(0, PATTERNS.size() - 1)]
	var spacing: float = scale * 1.9
	var offsets: Array = _offsets(pattern, spacing, rng)
	var accent: Color = theme.get("accent", Color(0.9, 0.4, 0.3, 1.0))
	var chain_radius: float = spacing * 1.7        # reach only immediate neighbours
	var mines: Array = []
	for off in offsets:
		var m: Area3D = MINE.new()
		m.ship = ship
		m.world = world
		m.theme = theme
		m.accent = accent
		m.enemy_scale = scale
		world.add_child(m)
		m.position = center + off
		m.configure_chain(chain_radius)
		mines.append(m)
	return mines

static func _offsets(pattern: String, spacing: float, rng: RandomNumberGenerator) -> Array:
	var pts: Array = []
	match pattern:
		"line_v":
			var n: int = rng.randi_range(3, 6)
			for i in range(n):
				pts.append(Vector3(0.0, (float(i) - (n - 1) * 0.5) * spacing, 0.0))
		"line_h":
			var n: int = rng.randi_range(3, 6)
			for i in range(n):
				pts.append(Vector3((float(i) - (n - 1) * 0.5) * spacing, 0.0, 0.0))
		"line_d":
			var n: int = rng.randi_range(3, 6)
			var sy: float = 1.0 if rng.randf() < 0.5 else -1.0
			for i in range(n):
				var t: float = (float(i) - (n - 1) * 0.5) * spacing * 0.78
				pts.append(Vector3(t, t * sy, 0.0))
		"ring":
			var n: int = rng.randi_range(6, 10)
			var r: float = spacing * float(n) / TAU     # circumference ~= n * spacing
			for i in range(n):
				var a: float = TAU * float(i) / float(n)
				pts.append(Vector3(cos(a) * r, sin(a) * r, 0.0))
		"diamond":
			var per: int = rng.randi_range(2, 3)         # mines added along each edge
			var r: float = spacing * float(per + 1)
			var corners := [Vector3(0, r, 0), Vector3(r, 0, 0), Vector3(0, -r, 0), Vector3(-r, 0, 0)]
			for c in range(4):
				var a: Vector3 = corners[c]
				var b: Vector3 = corners[(c + 1) % 4]
				for k in range(per + 1):                 # 0..per -> excludes the next corner
					pts.append(a.lerp(b, float(k) / float(per + 1)))
	return pts
