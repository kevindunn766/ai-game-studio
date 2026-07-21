extends Node

# Coarse ground LOD, decoupled from the object cells. The ground is a grid of SUBDIVIDED
# square tiles under `world_root` (so it scrolls + scales with the world), all sharing one
# cel-shaded ground material (ground.gdshader) which displaces them a little, paints a
# procedural soil base, and layers the generated top-down patch PNGs. As the world shrinks
# the tile SIZE grows (quantized to power-of-two octaves) so the on-screen tile count stays
# roughly constant instead of multiplying into hundreds of tiny tiles.

const GroundShader := preload("res://shaders/ground.gdshader")

# 3 shape variants per material -> a Texture2DArray each (built in _ensure_material).
const VARIANTS := {
	"grass": [preload("res://assets/ground/patch_grass_0.png"), preload("res://assets/ground/patch_grass_1.png"), preload("res://assets/ground/patch_grass_2.png")],
	"moss": [preload("res://assets/ground/patch_moss_0.png"), preload("res://assets/ground/patch_moss_1.png"), preload("res://assets/ground/patch_moss_2.png")],
	"rock": [preload("res://assets/ground/patch_rock_0.png"), preload("res://assets/ground/patch_rock_1.png"), preload("res://assets/ground/patch_rock_2.png")],
	"dirt": [preload("res://assets/ground/patch_dirt_0.png"), preload("res://assets/ground/patch_dirt_1.png"), preload("res://assets/ground/patch_dirt_2.png")],
	"pebble": [preload("res://assets/ground/patch_pebble_0.png"), preload("res://assets/ground/patch_pebble_1.png"), preload("res://assets/ground/patch_pebble_2.png")],
}

const SUBDIV: int = 24                         # tessellation per tile (for the displacement)

@export var target_render_tile: float = 1.6    # desired on-screen tile edge (render units)
@export var base_cell: float = 3.0             # smallest tile edge (content units) at level 0
@export var view_margin: float = 2.4           # cover well past the visible area
@export var camera_view: float = 2.5
@export var min_radius: float = 6.0
# Coverage must track the visible content area, which grows as 1/world_scale as the world
# shrinks through the tiers. The octave logic grows the tile SIZE by the same factor, so the
# on-screen tile COUNT stays roughly constant no matter how large this gets -- a low clamp
# (was 64) just starved coverage at deep scales, leaving the ground as a small patch over the
# backdrop. Kept finite as a runaway guard for extreme scales.
@export var max_radius: float = 100000.0

var world_root: Node3D = null
var height_field: RefCounted = null            # GroundHeight (set by main before update)

var _tiles: Dictionary = {}                    # "ix,iz" -> MeshInstance3D
var _level: int = -9999                        # current octave; grid rebuilds when it changes
var _cell: float = 3.0                         # content tile edge at the current level
var _mesh: PlaneMesh = null                    # shared subdivided mesh for the current level
var _mat: ShaderMaterial = null                # shared cel-shaded ground material


func _make_array(textures: Array) -> Texture2DArray:
	var imgs: Array[Image] = []
	for t in textures:
		imgs.append((t as Texture2D).get_image())
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr


func _ensure_material() -> void:
	if _mat != null or height_field == null:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = GroundShader
	for mat_name in VARIANTS.keys():
		_mat.set_shader_parameter("patch_" + mat_name, _make_array(VARIANTS[mat_name]))
	_mat.set_shader_parameter("height_tex", height_field.texture)
	_mat.set_shader_parameter("height_period", height_field.PERIOD)
	_mat.set_shader_parameter("height_amp", height_field.AMP)


func update(scroll: Vector2, world_scale: float) -> void:
	if world_root == null:
		return
	_ensure_material()
	if _mat != null:
		_mat.set_shader_parameter("world_scale", world_scale)
		_mat.set_shader_parameter("scroll", scroll)

	# Pick an octave so a tile is ~target_render_tile on screen: content size want =
	# target / world_scale, quantised to base_cell * 2^level.
	var want: float = target_render_tile / maxf(world_scale, 0.0001)
	var level: int = maxi(0, int(floor(log(maxf(want / base_cell, 1.0)) / log(2.0))))
	if level != _level:
		_set_level(level)

	var ts: float = _cell
	var r: float = clampf(camera_view * view_margin / maxf(world_scale, 0.0001), min_radius, max_radius)
	var cx: float = scroll.x
	var cz: float = scroll.y
	var ix0: int = int(floor((cx - r) / ts))
	var ix1: int = int(floor((cx + r) / ts))
	var iz0: int = int(floor((cz - r) / ts))
	var iz1: int = int(floor((cz + r) / ts))

	for key in _tiles.keys():
		var parts: PackedStringArray = key.split(",")
		var ix: int = int(parts[0])
		var iz: int = int(parts[1])
		if ix < ix0 or ix > ix1 or iz < iz0 or iz > iz1:
			_free_tile(key)

	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			var key: String = "%d,%d" % [ix, iz]
			if _tiles.has(key):
				continue
			_spawn_tile(ix, iz, ts, key)


func _set_level(level: int) -> void:
	for key in _tiles.keys():
		_free_tile(key)
	_level = level
	_cell = base_cell * pow(2.0, float(level))
	_mesh = PlaneMesh.new()
	_mesh.size = Vector2(_cell, _cell)
	_mesh.subdivide_width = SUBDIV
	_mesh.subdivide_depth = SUBDIV


func _spawn_tile(ix: int, iz: int, ts: float, key: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh                              # shared per-level subdivided mesh
	mi.material_override = _mat                  # shared cel-shaded ground material
	mi.position = Vector3((float(ix) + 0.5) * ts, 0.0, (float(iz) + 0.5) * ts)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader displaces the mesh, so give it a generous custom AABB to avoid frustum pop.
	mi.custom_aabb = AABB(Vector3(-ts, -2.0, -ts), Vector3(2.0 * ts, 4.0, 2.0 * ts))
	world_root.add_child(mi)
	_tiles[key] = mi


func _free_tile(key: String) -> void:
	var t: MeshInstance3D = _tiles.get(key, null)
	if t != null and is_instance_valid(t):
		t.queue_free()
	_tiles.erase(key)


func active_tile_count() -> int:
	return _tiles.size()
