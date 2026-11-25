extends Node3D

signal objective_changed(text: String)
signal exit_requested

@export_multiline var objective_initial: String = ""
@export_multiline var objective_cleared: String = ""
@export var required_spell: String = ""
@export var requires_whisper: bool = false
@export_range(1.0, 20.0, 0.25) var spell_radius: float = 7.0

@onready var spawn_point: Marker3D = $SpawnPoint
@onready var _gate: StaticBody3D = get_node_or_null("SpellGate") as StaticBody3D
@onready var _exit: Area3D = get_node_or_null("Exit") as Area3D
@onready var _secret: Node3D = get_node_or_null("Secret") as Node3D

var _exit_pending: bool = false

func _ready() -> void:
	if _gate != null:
		_gate.add_child(preload("res://scenes/floors/gate_motes.tscn").instantiate())
		VoiceReceiver.spell_heard.connect(_on_spell_heard)
	if _exit != null:
		_exit.body_entered.connect(_on_exit_body_entered)

func _on_spell_heard(spell: String, _confidence: float, _volume: float, _roll: Dictionary, is_whisper: bool) -> void:
	if _gate == null or is_queued_for_deletion() or spell != required_spell:
		return
	var player := get_tree().get_first_node_in_group("tower_player") as CharacterBody3D
	if player == null or player.global_position.distance_squared_to(_gate.global_position) > spell_radius * spell_radius:
		return
	if requires_whisper and not is_whisper:
		objective_changed.emit("Решётка слышит крик. Прошепчи «Ноктар» или нажми Shift+2 рядом с ней.")
		return
	_gate.queue_free()
	_gate = null
	if _secret != null:
		_secret.show()
	objective_changed.emit(objective_cleared)

func _on_exit_body_entered(body: Node3D) -> void:
	if _exit_pending or _gate != null or is_queued_for_deletion() or not body.is_in_group("tower_player"):
		return
	_exit_pending = true
	exit_requested.emit()
