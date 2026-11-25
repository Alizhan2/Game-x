extends Node

## Управляет 4 этажами Башни Согласия (Глава I).
## Переносит память AdaptiveAI между уровнями и поддерживает F9 для жюри.

signal level_loaded(floor_index: int, floor_title: String)

const FLOORS: Array[Dictionary] = [
	{
		"index": 1,
		"title": "Этаж 1: Вход и Гримуар Миры",
		"scene_path": "res://scenes/floors/floor_1_tutorial.tscn",
		"primary_word": "virdan",
	},
	{
		"index": 2,
		"title": "Этаж 2: Зал Эльфов (Отложенная весна)",
		"scene_path": "res://scenes/floors/floor_2_elves.tscn",
		"primary_word": "virdan",
	},
	{
		"index": 3,
		"title": "Этаж 3: Склеп Памяти",
		"scene_path": "res://scenes/floors/floor_3_undead.tscn",
		"primary_word": "noktar",
	},
	{
		"index": 4,
		"title": "Этаж 4: Вершина Согласия — Хранитель",
		"scene_path": "res://scenes/floors/floor_4_boss.tscn",
		"primary_word": "targum",
	},
]

@export var active_floor_container_path: NodePath
@export var player_path: NodePath

var current_floor_index: int = 1
var _current_floor_node: Node = null

func _ready() -> void:
	load_floor(1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jury_boss_skip"):
		jump_to_boss_for_jury()

func load_floor(floor_index: int) -> void:
	var clamped := clampi(floor_index, 1, FLOORS.size())
	var floor_info := FLOORS[clamped - 1]
	current_floor_index = clamped
	GameState.set_floor(clamped)

	var scene_path := str(floor_info["scene_path"])
	if _current_floor_node != null and is_instance_valid(_current_floor_node):
		_current_floor_node.queue_free()
		_current_floor_node.get_parent().remove_child(_current_floor_node)
		_current_floor_node = null

	if ResourceLoader.exists(scene_path) and active_floor_container_path != NodePath():
		var container := get_node_or_null(active_floor_container_path)
		if container != null:
			var packed := load(scene_path) as PackedScene
			if packed != null:
				_current_floor_node = packed.instantiate()
				container.add_child(_current_floor_node)

	level_loaded.emit(clamped, str(floor_info["title"]))

func advance_to_next_floor() -> void:
	if current_floor_index < FLOORS.size():
		load_floor(current_floor_index + 1)

func jump_to_boss_for_jury() -> void:
	GameState.unlock_word("virdan")
	GameState.unlock_word("noktar")
	GameState.unlock_word("targum")
	load_floor(4)
