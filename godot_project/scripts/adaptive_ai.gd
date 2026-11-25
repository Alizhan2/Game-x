extends Node

## Локальный живой ИИ-соперник для Echoes of Arcana.
## Отслеживает спам заклинаний, строит матрицу переходов игрока,
## включает контр-щит и плавно корректирует сложность (DDA).

enum Difficulty {
	APPRENTICE,
	MAGE,
	ARCHMAGE,
}

signal counter_shield_changed(blocked_spell: String)
signal taunt_triggered(message: String)
signal difficulty_changed(level: int)
signal adaptation_updated(stats: Dictionary)

const SPELLS: Array[String] = ["virdan", "noktar", "targum"]
const MAX_HISTORY: int = 12

var current_difficulty: Difficulty = Difficulty.MAGE
var active_counter_spell: String = ""
var dda_modifier: float = 1.0

var _cast_history: Array[String] = []
var _spell_counts: Dictionary = {
	"virdan": 0,
	"noktar": 0,
	"targum": 0,
}
var _transitions: Dictionary = {}
var _consecutive_hits_taken: int = 0
var _consecutive_clean_casts: int = 0

func _ready() -> void:
	if Engine.has_singleton("VoiceReceiver") or get_node_or_null("/root/VoiceReceiver") != null:
		VoiceReceiver.spell_heard.connect(_on_spell_heard)

# Keyboard selection is also available in the starter arena before the menu loads.
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1: set_difficulty(Difficulty.APPRENTICE)
			KEY_F2: set_difficulty(Difficulty.MAGE)
			KEY_F3: set_difficulty(Difficulty.ARCHMAGE)

func set_difficulty(diff: Difficulty) -> void:
	if diff == current_difficulty:
		return
	current_difficulty = diff
	if active_counter_spell != "":
		active_counter_spell = ""
		counter_shield_changed.emit("")
	difficulty_changed.emit(int(diff))
	_emit_stats()

func reset_for_new_run() -> void:
	active_counter_spell = ""
	dda_modifier = 1.0
	_cast_history.clear()
	_transitions.clear()
	_spell_counts = {"virdan": 0, "noktar": 0, "targum": 0}
	_consecutive_hits_taken = 0
	_consecutive_clean_casts = 0
	counter_shield_changed.emit("")
	_emit_stats()

func is_spell_countered(spell: String) -> bool:
	return active_counter_spell != "" and active_counter_spell == spell

func predict_next_spell() -> String:
	if _cast_history.is_empty():
		return ""
	var last_spell: String = _cast_history[_cast_history.size() - 1]
	if not _transitions.has(last_spell):
		return last_spell
	var next_map: Dictionary = _transitions[last_spell]
	var best_spell := ""
	var best_count := 0
	for candidate in next_map.keys():
		var count: int = int(next_map[candidate])
		if count > best_count:
			best_count = count
			best_spell = str(candidate)
	return best_spell

func record_player_hit(took_damage: bool) -> void:
	if took_damage:
		_consecutive_hits_taken += 1
		_consecutive_clean_casts = 0
		if _consecutive_hits_taken >= 2:
			dda_modifier = maxf(0.75, dda_modifier - 0.08)
	else:
		_consecutive_hits_taken = 0
		_consecutive_clean_casts += 1
		if _consecutive_clean_casts >= 4:
			dda_modifier = minf(1.25, dda_modifier + 0.05)
	_emit_stats()

func get_damage_multiplier() -> float:
	var base := 1.0
	match current_difficulty:
		Difficulty.APPRENTICE:
			base = 0.75
		Difficulty.MAGE:
			base = 1.0
		Difficulty.ARCHMAGE:
			base = 1.3
	return base * dda_modifier

func get_difficulty_label() -> String:
	match current_difficulty:
		Difficulty.APPRENTICE:
			return "Ученик"
		Difficulty.MAGE:
			return "Маг"
		Difficulty.ARCHMAGE:
			return "Архимаг"
	return "Маг"

func _on_spell_heard(spell: String, _conf: float, _vol: float, d20: Dictionary, _whisper: bool) -> void:
	if spell not in SPELLS or d20.get("d20", 0) == 1:
		return

	if not _cast_history.is_empty():
		var prev := _cast_history[_cast_history.size() - 1]
		if not _transitions.has(prev):
			_transitions[prev] = {}
		var row: Dictionary = _transitions[prev]
		row[spell] = int(row.get(spell, 0)) + 1

	_cast_history.append(spell)
	if _cast_history.size() > MAX_HISTORY:
		_cast_history.pop_front()

	_spell_counts[spell] = int(_spell_counts.get(spell, 0)) + 1
	# Capture the outcome of THIS cast before arming a possible shield for the next.
	# The autoload subscribes before the scene's player and enemies.
	var repeats := _count_trailing_repeats(spell)
	var threshold := 3 if current_difficulty == Difficulty.APPRENTICE else 2
	var spam := repeats >= threshold
	d20["countered"] = is_spell_countered(spell) or spam
	_evaluate_counter_shield(spell, spam)
	_emit_stats()

func _evaluate_counter_shield(spell: String, spam: bool) -> void:
	var next_shield := ""
	var taunt := "Архив-0: Неожиданная смена школы… Корректирую модель."
	if spam:
		next_shield = spell
		taunt = "Архив-0: Паттерн «%s» изучен. Активирован контр-щит!" % spell.to_upper()
	elif current_difficulty == Difficulty.ARCHMAGE and _cast_history.size() >= 4:
		var prediction := predict_next_spell()
		if prediction != spell:
			next_shield = prediction
			taunt = "Архив-0: Я предугадал твой следующий слог — «%s»!" % prediction.to_upper()
	if active_counter_spell != next_shield:
		active_counter_spell = next_shield
		counter_shield_changed.emit(next_shield)
		taunt_triggered.emit(taunt)

func _count_trailing_repeats(target: String) -> int:
	var count := 0
	for idx in range(_cast_history.size() - 1, -1, -1):
		if _cast_history[idx] == target:
			count += 1
		else:
			break
	return count

func _emit_stats() -> void:
	adaptation_updated.emit({
		"difficulty": get_difficulty_label(),
		"counter_spell": active_counter_spell,
		"predicted_next": predict_next_spell(),
		"dda_modifier": snappedf(dda_modifier, 0.01),
		"counts": _spell_counts.duplicate(),
	})
