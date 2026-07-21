extends RefCounted

# Parses biome_attribute_table.csv (Kevin's master content table) into a data
# dictionary the level roll drives off. One row per biome:
#   Biome, Structure(s), View(s), Gravity Y/N, Enemies (3), Object 1..10
#
# Returns: biome_name -> {
#   structures: [csv structure tokens],       # e.g. "Landscape", "Tunneling Caves"
#   views:      [game viewpoint ids],         # "thirdperson", "isometric", ...
#   gravity:    bool,
#   enemies:    [drifter, hunter, mines],     # the 3 named enemies
#   objects:    [10 object names],            # biome-specific feature objects
# }
#
# Parsed once and cached. FileAccess.get_csv_line handles the quoted multi-value
# cells, and works headless on res:// (no import step needed for run-from-source).

const PATH := "res://biome_attribute_table.csv"

# CSV view tokens -> the game's viewpoint ids.
const VIEW_MAP := {
	"3rd": "thirdperson",
	"3/4": "threequarter",
	"Iso": "isometric",
	"SS": "sidescroll",
	"TD": "topdown",
}

static var _cache: Dictionary = {}

static func table() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("[BiomeTable] could not open " + PATH)
		return _cache
	f.get_csv_line()   # header
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.size() < 15:
			continue
		var biome: String = row[0].strip_edges()
		if biome == "":
			continue
		var objects: Array = []
		for i in range(5, 15):
			var o: String = row[i].strip_edges()
			if o != "":
				objects.append(o)
		_cache[biome] = {
			"structures": _split(row[1]),
			"views": _views(row[2]),
			"gravity": row[3].strip_edges().to_upper().begins_with("Y"),
			"enemies": _split(row[4]),
			"objects": objects,
		}
	f.close()
	return _cache

static func _split(cell: String) -> Array:
	var out: Array = []
	for part in cell.split(","):
		var p: String = part.strip_edges()
		if p != "":
			out.append(p)
	return out

static func _views(cell: String) -> Array:
	var out: Array = []
	for part in cell.split(","):
		var p: String = part.strip_edges()
		if VIEW_MAP.has(p):
			out.append(VIEW_MAP[p])
	return out
