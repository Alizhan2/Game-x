extends "res://scenes/floors/tower_floor.gd"

const Keeper = preload("res://scripts/keeper_boss.gd")
const WORDS := {"virdan": "Вирдан (1)", "noktar": "Ноктар (2)", "targum": "Таргум (3)"}

@onready var _keeper: Keeper = $KeeperBoss

func _ready() -> void:
	super._ready()
	set_process(false)

func _on_spell_heard(spell: String, confidence: float, volume: float, roll: Dictionary, whisper: bool) -> void:
	if _keeper.current_phase == Keeper.Phase.FINISHED:
		return
	super._on_spell_heard(spell, confidence, volume, roll, whisper)
	if is_queued_for_deletion() or (_gate != null and _keeper.current_phase != Keeper.Phase.FINAL_CHOICE):
		return
	# KeeperBoss is a child: its spell handler runs before the floor's handler.
	set_process(_keeper.current_phase == Keeper.Phase.COMBO_10001)
	match _keeper.current_phase:
		Keeper.Phase.ESCAPE_ROOTS:
			objective_changed.emit(objective_cleared)
		Keeper.Phase.CENSOR_SPIRIT:
			objective_changed.emit("Корни сработали. Раскрой Хранителя словом «Ноктар» (2).")
		Keeper.Phase.COMBO_10001:
			var missing: PackedStringArray = []
			for word: String in WORDS:
				if not _keeper._combo_heard.has(word):
					missing.append(WORDS[word])
			objective_changed.emit("Комбо %d/3. Осталось: %s. Уложись в 8 секунд, делая паузу около секунды." % [WORDS.size() - missing.size(), ", ".join(missing)])
		Keeper.Phase.FINAL_CHOICE:
			objective_changed.emit("Комбо сработало — 3/3! Для «Переводчика» произнеси ещё одно слово или нажми 1. Для «Цены Тишины» удерживай 0 пять секунд.")

func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > _keeper._combo_deadline_msec:
		set_process(false)
		objective_changed.emit("Время комбо истекло. Начни заново: 1 → 2 → 3, по одному нажатию в секунду.")
