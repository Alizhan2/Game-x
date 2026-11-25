extends CombatGuard

signal objective_changed(text: String)
signal ward_broken

enum Phase { BEAM_SHIELD, ESCAPE_ROOTS, CENSOR_SPIRIT, COMBO_10001, FINAL_CHOICE, FINISHED }

const COMBO := ["virdan", "noktar", "targum"]
const COMBO_WINDOW_MSEC := 8000
const SILENCE_MSEC := 5000
const FIRST_OBJECTIVE := "Подойди к Хранителю. Когда он приготовит луч, подними щит «Таргум» (3)."

@export_node_path("Marker3D") var retreat_point: NodePath
@onready var _retreat := get_node_or_null(retreat_point) as Marker3D

var current_phase := Phase.BEAM_SHIELD
var _combo_step := 0
var _combo_deadline_msec := 0
var _choice_started_msec := 0


func _ready() -> void:
	super._ready()
	beam_blocked.connect(_on_beam_blocked)
	VoiceReceiver.spell_heard.connect(_on_spell_heard)
	VoiceReceiver.silence_updated.connect(_on_silence_updated)


func _should_cast_beam(distance: float) -> bool:
	return current_phase == Phase.BEAM_SHIELD or super._should_cast_beam(distance)


func _physics_process(delta: float) -> void:
	if current_phase == Phase.COMBO_10001 and _combo_step > 0 and Time.get_ticks_msec() > _combo_deadline_msec:
		_combo_step = 0
		_show_combo()
	super._physics_process(delta)


func _track_player(player: ArcanaPlayer, delta: float) -> bool:
	if current_phase == Phase.ESCAPE_ROOTS and _retreat != null:
		var offset := _retreat.global_position - global_position
		offset.y = 0.0
		if offset.length() > 0.1:
			rotation.y = atan2(offset.x, offset.z)
			global_position += offset.limit_length(approach_speed * 1.6 * delta)
			return true
	return super._track_player(player, delta)


func _on_defeated() -> void:
	# Melee can stagger the Keeper. The three schools break the ward.
	health = max_health
	bind_roots(3.0)


func _on_beam_blocked(player: ArcanaPlayer) -> void:
	if current_phase != Phase.BEAM_SHIELD:
		return
	_SpellVFX.spawn_beam(get_parent(), player.global_position + Vector3.UP,
			global_position + 1.3 * Vector3.UP, Color("ffc65c"))
	current_phase = Phase.ESCAPE_ROOTS
	objective_changed.emit("Хранитель отступает. Догони его и свяжи корнями «Вирдан» (1).")


func _on_spell_heard(spell: String, _conf: float, _vol: float, d20: Dictionary, _whisper: bool) -> void:
	if not is_inside_tree() or spell not in COMBO or current_phase == Phase.FINISHED:
		return
	if current_phase == Phase.FINAL_CHOICE:
		_finish("translator")
		return
	if d20["d20"] == 1 or d20.get("countered", false):
		return
	var player := get_tree().get_first_node_in_group(&"combat_player") as ArcanaPlayer
	if player == null or global_position.distance_to(player.global_position) > player.spell_radius:
		return
	match current_phase:
		Phase.ESCAPE_ROOTS:
			if spell == "virdan":
				current_phase = Phase.CENSOR_SPIRIT
				GameState.set_censorship(true)
				objective_changed.emit("Архив стирает имена. Раскрой его дух словом «Ноктар» (2).")
		Phase.CENSOR_SPIRIT:
			if spell == "noktar":
				GameState.set_censorship(false)
				current_phase = Phase.COMBO_10001
				_show_combo()
		Phase.COMBO_10001:
			_cast_combo(spell)


func _cast_combo(spell: String) -> void:
	var now := Time.get_ticks_msec()
	if now > _combo_deadline_msec or spell != COMBO[_combo_step]:
		_combo_step = 0
	if spell == COMBO[_combo_step]:
		if _combo_step == 0:
			_combo_deadline_msec = now + COMBO_WINDOW_MSEC
		_combo_step += 1
	if _combo_step < COMBO.size():
		_show_combo()
		return

	current_phase = Phase.FINAL_CHOICE
	VoiceReceiver.reset_cast_cooldown()
	_choice_started_msec = now
	_windup = 0.0
	_telegraph_ring.hide()
	_action_until_msec = 0
	_play_clip([&"Idle", &"CharacterArmature|Idle"])
	set_physics_process(false)
	remove_from_group(&"combat_guards")
	_status.hide()
	ward_broken.emit()
	objective_changed.emit("Печать снята. Произнеси любое заклинание (1/2/3), чтобы вернуть магию. Или молчи пять секунд у микрофона либо удерживай 0.")


func _show_combo() -> void:
	objective_changed.emit("Три языка за 8 секунд: Вирдан → Ноктар → Таргум (1 → 2 → 3). Принято: %d/3." % _combo_step)


func _on_silence_updated(seconds: float) -> void:
	if is_inside_tree() and current_phase == Phase.FINAL_CHOICE and seconds >= SILENCE_MSEC / 1000.0:
		if Time.get_ticks_msec() - _choice_started_msec >= SILENCE_MSEC:
			_finish("silence")


func _finish(ending: String) -> void:
	current_phase = Phase.FINISHED
	GameState.finish_chapter_one(ending)
