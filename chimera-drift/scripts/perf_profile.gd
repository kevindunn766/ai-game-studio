extends Node

# Autoload (PerfProfile). On the FIRST launch it best-guesses a hardware
# performance rating, caches it to user://, and exposes quality knobs the rest of
# the game reads (particle count, view distance, skybox quality). Runs once; later
# launches just load the cached profile. Delete user://perf_profile.cfg (or call
# rerate()) to re-detect.
#
# "Best guess" is a heuristic (GPU name/type + CPU cores + RAM) rather than a
# live benchmark -- robust, instant, and vsync-proof. Under GL Compatibility the
# adapter *type* is often unreliable, so the GPU *name* string is the main signal.
# On a typical dev laptop this lands at HIGH/ULTRA (tops out), which is the intent.

enum Tier { LOW, MEDIUM, HIGH, ULTRA }

const CFG_PATH := "user://perf_profile.cfg"

var tier: int = Tier.ULTRA
# Derived knobs (defaults = top tier so anything reading early gets full quality).
var particle_scale: float = 1.0       # multiplier on procedural particle amounts
var view_distance_scale: float = 1.0  # multiplier on how far generators stream
var sky_quality: int = 3              # 0..3 -> sky sample counts / radiance / layers

func _ready() -> void:
	if not _load():
		tier = _rate()
		_save()
	_apply()
	print("[PerfProfile] tier=%s  particles=%.2f  view=%.2f  sky_q=%d  (GPU: %s)" % [
		Tier.keys()[tier], particle_scale, view_distance_scale, sky_quality,
		RenderingServer.get_video_adapter_name()])

# --- rating ----------------------------------------------------------------
func _rate() -> int:
	var score: float = _gpu_score()
	var cores: int = OS.get_processor_count()
	if cores >= 12: score += 1.0
	elif cores >= 8: score += 0.5
	elif cores < 4: score -= 1.0

	var mem_gb: float = _mem_gb()
	if mem_gb >= 32.0: score += 1.0
	elif mem_gb >= 16.0: score += 0.5
	elif mem_gb > 0.0 and mem_gb < 8.0: score -= 1.0

	if score >= 3.5: return Tier.ULTRA
	if score >= 2.5: return Tier.HIGH
	if score >= 1.5: return Tier.MEDIUM
	return Tier.LOW

# GPU base score from the adapter name (+ type as a tiebreak).
func _gpu_score() -> float:
	var name: String = RenderingServer.get_video_adapter_name().to_lower()
	# Software / CPU rasterizer -> weakest.
	if name.contains("llvmpipe") or name.contains("swiftshader") or name.contains("software"):
		return 0.0
	# Discrete GPUs.
	if name.contains("rtx") or name.contains("geforce") or name.contains("gtx") \
			or name.contains("quadro") or name.contains("radeon rx") or name.contains("arc ") \
			or name.contains("radeon pro"):
		return 3.0
	# Apple Silicon: strong integrated.
	if name.contains("apple m"):
		return 3.0
	# Integrated (Intel UHD/HD/Iris/Xe, AMD Radeon(TM) Graphics / Vega iGPU).
	if name.contains("intel") or name.contains("iris") or name.contains("uhd") \
			or name.contains("radeon") or name.contains("vega") or name.contains("mesa"):
		return 2.0
	# Unknown -> assume capable (the intent is to top out unless clearly weak).
	var t: int = RenderingServer.get_video_adapter_type()
	if t == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
		return 3.0
	return 2.5

func _mem_gb() -> float:
	var info: Dictionary = OS.get_memory_info()
	var phys: int = int(info.get("physical", -1))
	return float(phys) / 1073741824.0 if phys > 0 else -1.0

# --- knob mapping ----------------------------------------------------------
func _apply() -> void:
	match tier:
		Tier.ULTRA:
			particle_scale = 1.0; view_distance_scale = 1.0; sky_quality = 3
		Tier.HIGH:
			particle_scale = 1.0; view_distance_scale = 1.0; sky_quality = 2
		Tier.MEDIUM:
			particle_scale = 0.5; view_distance_scale = 0.75; sky_quality = 1
		_:  # LOW
			particle_scale = 0.0; view_distance_scale = 0.5; sky_quality = 0

# Sky radiance cubemap resolution per tier (IBL cost).
func sky_radiance_size() -> int:
	match sky_quality:
		3: return Sky.RADIANCE_SIZE_256
		2: return Sky.RADIANCE_SIZE_128
		1: return Sky.RADIANCE_SIZE_64
		_: return Sky.RADIANCE_SIZE_32

# --- persistence -----------------------------------------------------------
func _load() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return false
	tier = int(cfg.get_value("perf", "tier", Tier.ULTRA))
	return true

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("perf", "tier", tier)
	cfg.set_value("perf", "gpu", RenderingServer.get_video_adapter_name())
	cfg.set_value("perf", "cores", OS.get_processor_count())
	cfg.set_value("perf", "mem_gb", _mem_gb())
	cfg.save(CFG_PATH)

# Force a fresh detection (e.g. from a future settings menu).
func rerate() -> void:
	tier = _rate()
	_save()
	_apply()
