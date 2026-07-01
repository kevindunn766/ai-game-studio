class_name ScoreLabel extends Label3D

@export var manager: Node3D

func _ready() -> void:
    text = "0"
    if manager and manager.has_signal("food_eaten"):
        manager.food_eaten.connect(_on_score_changed)
    if manager and manager.has_signal("game_over"):
        manager.game_over.connect(_on_game_over)


func _on_score_changed(new_score: int) -> void:
    text = str(new_score)


func _on_game_over(final_score: int) -> void:
    text = "GAME OVER\n%d" % final_score
