extends Node

# Persistent player PROFILE -- survives across runs AND sessions; only a manual wipe
# (title-screen button) or an uninstall clears it. Stores:
#   - beaten: has the base game been beaten (ULTRA/final boss downed)? Once true,
#     NEW GAME PLUS is unlocked and every future run starts in the endless scrambled
#     NG+ mode (LevelSeed reads this at run start).
#   - best-time RECORDS for the post-game time-attack: fastest boss fight per boss
#     TYPE, fastest single level clear, and the deepest level reached.
# Saved to user://profile.cfg (ConfigFile, same pattern as PerfProfile). Reached by
# other scripts via the /root/Profile autoload; LevelSeed uses get_node_or_null so it
# still compiles when preloaded outside the autoload context (headless -s tests).

const PATH := "user://profile.cfg"

var beaten: bool = false
var boss_best: Dictionary = {}       # boss type key ("Core"/"Wall"/"Ring"/"Super …"/"Ultra") -> fastest seconds
var level_best: float = 0.0          # fastest level clear, seconds (0 = none yet)
var best_sector: int = 0             # deepest level reached (best "game")

func _ready() -> void:
	_load()

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	beaten = bool(cfg.get_value("progress", "beaten", false))
	best_sector = int(cfg.get_value("progress", "best_sector", 0))
	level_best = float(cfg.get_value("records", "level_best", 0.0))
	var bb: Variant = cfg.get_value("records", "boss_best", {})
	boss_best = bb if bb is Dictionary else {}

func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "beaten", beaten)
	cfg.set_value("progress", "best_sector", best_sector)
	cfg.set_value("records", "level_best", level_best)
	cfg.set_value("records", "boss_best", boss_best)
	cfg.save(PATH)

# Base game beaten -> unlock persistent NG+. Idempotent.
func mark_beaten() -> void:
	if beaten:
		return
	beaten = true
	_save()

# Record a boss-fight time. Returns true if it set a NEW best for that boss type.
func record_boss_time(key: String, seconds: float) -> bool:
	if key == "" or seconds <= 0.0:
		return false
	var prev: float = float(boss_best.get(key, 0.0))
	if prev <= 0.0 or seconds < prev:
		boss_best[key] = seconds
		_save()
		return true
	return false

func record_level_time(seconds: float) -> bool:
	if seconds <= 0.0:
		return false
	if level_best <= 0.0 or seconds < level_best:
		level_best = seconds
		_save()
		return true
	return false

func record_sector(sector: int) -> bool:
	if sector > best_sector:
		best_sector = sector
		_save()
		return true
	return false

func has_progress() -> bool:
	return beaten or best_sector > 0 or level_best > 0.0 or not boss_best.is_empty()

# Reset ONLY the NG+ unlock -> back to the base game. Best-time RECORDS (boss_best,
# level_best, best_sector) are KEPT so the time-attack history survives.
func reset_ng_plus() -> void:
	if not beaten:
		return
	beaten = false
	_save()
