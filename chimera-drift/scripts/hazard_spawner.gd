extends RefCounted

# Factory for the three slow-damage hazard types, mirroring EnemySpawner. Fields are
# plain Node3D particle clouds; leeches + graspers are enemy_base creatures (so they
# share the hurtbox/destroy/explode path). Generators position them shape-
# appropriately and set .world on the enemy_base ones (needed for the death VFX).

const FIELD := preload("res://scripts/hazard_field.gd")
const LEECH := preload("res://scripts/hazard_leech.gd")
const GRASPER := preload("res://scripts/hazard_grasper.gd")
const TURRET := preload("res://scripts/turret.gd")
const PUSH := preload("res://scripts/hazard_push.gd")

static func create(kind: String, ship: Node3D, theme: Dictionary, scale: float, opts: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var accent: Color = theme.get("accent", Color(0.9, 0.5, 0.3, 1.0))
	match kind:
		"field":
			var f := FIELD.new()
			f.ship = ship
			f.accent = accent
			f.scale_ref = scale
			f.variant = "vent" if (opts.get("allow_vent", true) and rng.randf() < 0.5) else "mist"
			return f
		"leech":
			var l = LEECH.new()
			l.ship = ship
			l.theme = theme
			l.accent = accent
			l.enemy_scale = scale
			l.spawn_mode = opts.get("mode", "drop")
			return l
		"grasper":
			var g = GRASPER.new()
			g.ship = ship
			g.theme = theme
			g.accent = accent
			g.enemy_scale = scale
			return g
		"turret":
			var t = TURRET.new()
			t.ship = ship
			t.theme = theme
			t.accent = accent
			t.enemy_scale = scale
			return t
		"push":
			var pu := PUSH.new()
			pu.ship = ship
			pu.accent = accent
			pu.scale_ref = scale
			return pu
		"waterfall":
			# A cliff waterfall: a continuous cascade that shoves the ship off course.
			var w := PUSH.new()
			w.ship = ship
			w.accent = accent
			w.scale_ref = scale
			w.variant = "waterfall"
			return w
		"lava":
			# A cliff lava flow: damage-over-time field that ALSO pushes.
			var lv := FIELD.new()
			lv.ship = ship
			lv.accent = accent
			lv.scale_ref = scale
			lv.variant = "lava"
			return lv
	return null
