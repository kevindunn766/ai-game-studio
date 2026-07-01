class_name ScoreLabel extends Label3D
signal safe(s: int)

var score: int = 0:
	set(v):
		score = max(0, v)
		_apply_text()

func _ready() -> void:
	_apply_text()

func reset() -> void:
	score = 0
	_apply_text()

func add(pts: int = 1) -> int:
	score += pts
	_apply_text()
	safe.emit(score)
	return score

func _apply_text() -> void:
	text = "SCORE: %d" % score
	pixel_size = 0.15
