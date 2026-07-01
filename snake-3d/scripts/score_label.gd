class_name ScoreLabel extends Label3D

@export var manager_path: NodePath = ^"../GameManager"


func _ready() -> void:
	var mgr: Node3D = get_node_or_null(manager_path)
	if mgr == null:
		mgr = get_parent()
	if mgr and mgr.has_signal("food_eaten"):
		if not mgr.food_eaten.is_connected(_on_score_changed):
			mgr.food_eaten.connect(_on_score_changed)
	if mgr and mgr.has_signal("game_over"):
		if not mgr.game_over.is_connected(_on_game_over):
			mgr.game_over.connect(_on_game_over)


func _on_score_changed(new_score: int) -> void:
	text = "%d" % new_score


func _on_game_over(final_score: int) -> void:
	text = "GAME OVER\n%d" % final_score
