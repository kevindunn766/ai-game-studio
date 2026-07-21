extends CanvasLayer

# Screen-space LENS FLARE overlay for the showcase screens. Projects a light's world
# direction to screen space each frame and drives lens_flare.gdshader on a full-rect
# ColorRect, so the flare tracks the sun as the camera orbits and fades out when the
# sun leaves frame or falls behind the camera. Sits BELOW the menu UI (layer -1) so
# text/buttons stay crisp on top. Set `sun_direction` (world dir camera->sun) + optional
# `flare_color` / `base_intensity` before add_child.

const FLARE_SHADER := preload("res://shaders/lens_flare.gdshader")

var sun_direction: Vector3 = Vector3(0.3, 0.5, 0.6)
var flare_color: Color = Color(1.0, 0.92, 0.78)
var base_intensity: float = 0.7

var _mat: ShaderMaterial = null

func _ready() -> void:
	layer = -1                                   # over the 3D, under the menu UI (layer 0)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = FLARE_SHADER
	_mat.set_shader_parameter("flare_color", Vector3(flare_color.r, flare_color.g, flare_color.b))
	_mat.set_shader_parameter("intensity", 0.0)
	rect.material = _mat
	add_child(rect)

# Retarget the flare (direction cam->sun) + recolour it. Safe to call any time (e.g.
# each level when the biome's sun changes).
func set_sun(dir: Vector3, color: Color) -> void:
	sun_direction = dir
	flare_color = color
	if _mat != null:
		_mat.set_shader_parameter("flare_color", Vector3(color.r, color.g, color.b))

func _process(_delta: float) -> void:
	if _mat == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_mat.set_shader_parameter("intensity", 0.0)
		return
	var dir: Vector3 = sun_direction.normalized()
	var forward: Vector3 = -cam.global_transform.basis.z
	var facing: float = forward.dot(dir)
	var world_pt: Vector3 = cam.global_position + dir * 2000.0
	if facing <= 0.02 or cam.is_position_behind(world_pt):
		_mat.set_shader_parameter("intensity", 0.0)
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var sp: Vector2 = cam.unproject_position(world_pt)
	var uv: Vector2 = Vector2(sp.x / vp.x, sp.y / vp.y)
	# Persist a little past the frame edge, then fade.
	var m: float = minf(minf(uv.x, 1.0 - uv.x), minf(uv.y, 1.0 - uv.y))
	var edge: float = clampf(smoothstep(-0.25, 0.1, m), 0.0, 1.0)
	_mat.set_shader_parameter("flare_pos", uv)
	_mat.set_shader_parameter("aspect", vp.x / vp.y)
	_mat.set_shader_parameter("intensity", base_intensity * clampf(facing, 0.0, 1.0) * edge)
