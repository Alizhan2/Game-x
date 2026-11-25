extends Node3D

const LevelManager = preload("res://scripts/level_manager.gd")
const TowerFloor = preload("res://scenes/floors/tower_floor.gd")

@onready var _manager: LevelManager = $LevelManager
@onready var _player: ArcanaPlayer = $Player
@onready var _floor_container: Node3D = $ActiveFloor
@onready var _floor_title: Label = $CanvasLayer/HudPanel/VBox/FloorTitle
@onready var _objective: Label = $CanvasLayer/HudPanel/VBox/ObjectiveLabel

var _active_floor: TowerFloor

func _ready() -> void:
	_manager.level_loaded.connect(_on_level_loaded)
	GameState.ending_reached.connect(_on_ending_reached)
	var floor_index := _manager.current_floor_index
	_on_level_loaded(floor_index, str(LevelManager.FLOORS[floor_index - 1]["title"]))

func _on_level_loaded(_floor_index: int, title: String) -> void:
	_floor_title.text = title
	if GameState.ui_censored:
		GameState.set_censorship(false)
	_active_floor = null
	for child in _floor_container.get_children():
		if child.is_queued_for_deletion():
			_floor_container.remove_child(child)
			continue
		_active_floor = child as TowerFloor
		break
	if not is_instance_valid(_active_floor):
		return
	_player.set_floor_spawn(_active_floor.spawn_point.global_position)
	_objective.text = _active_floor.objective_initial
	_active_floor.objective_changed.connect(_on_objective_changed)
	_active_floor.exit_requested.connect(_on_exit_requested)

func _on_objective_changed(text: String) -> void:
	_objective.text = text

func _on_exit_requested() -> void:
	# Physics signals arrive while the space is locked. Swap scenes after the step.
	_manager.advance_to_next_floor.call_deferred()

func _on_ending_reached(ending_id: String) -> void:
	match ending_id:
		"translator":
			_objective.text = "Концовка «Переводчик». Магия возвращается в Башню."
		"silence":
			_objective.text = "Концовка «Цена Тишины». Источник Перворечи угас."
