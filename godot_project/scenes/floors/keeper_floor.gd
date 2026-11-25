extends "res://scenes/floors/tower_floor.gd"

const Keeper = preload("res://scripts/keeper_boss.gd")

@onready var _keeper: Keeper = $KeeperBoss

func _ready() -> void:
	super._ready()
	objective_initial = Keeper.FIRST_OBJECTIVE
	_keeper.objective_changed.connect(objective_changed.emit)
	_keeper.ward_broken.connect($ExitWard.queue_free)
