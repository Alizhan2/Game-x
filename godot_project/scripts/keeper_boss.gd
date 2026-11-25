extends CombatGuard

enum Phase {
	BEAM_SHIELD,
	ESCAPE_ROOTS,
	CENSOR_SPIRIT,
	COMBO_10001,
	FINAL_CHOICE,
	FINISHED,
}

var current_phase: Phase = Phase.BEAM_SHIELD
var _combo_heard: Dictionary = {}
var _combo_deadline_msec: int = 0

func _ready() -> void:
	super._ready()
	VoiceReceiver.spell_heard.connect(_on_spell_heard)
	VoiceReceiver.silence_updated.connect(_on_silence_updated)

# A broken combat stance staggers the Keeper. The ritual still determines the ending.
func _on_defeated() -> void:
	health = max_health
	bind_roots(3.0)

func _on_spell_heard(spell: String, _conf: float, _vol: float, d20: Dictionary, _whisper: bool) -> void:
	if d20["d20"] == 1:
		return
	match current_phase:
		Phase.BEAM_SHIELD:
			if spell == "targum":
				current_phase = Phase.ESCAPE_ROOTS
		Phase.ESCAPE_ROOTS:
			if spell == "virdan":
				current_phase = Phase.CENSOR_SPIRIT
				GameState.set_censorship(true)
		Phase.CENSOR_SPIRIT:
			if spell == "noktar":
				GameState.set_censorship(false)
				current_phase = Phase.COMBO_10001
				_combo_heard.clear()
				_combo_deadline_msec = Time.get_ticks_msec() + 8000
		Phase.COMBO_10001:
			var now := Time.get_ticks_msec()
			if now > _combo_deadline_msec:
				_combo_heard.clear()
				_combo_deadline_msec = now + 8000
			_combo_heard[spell] = true
			if _combo_heard.has("virdan") and _combo_heard.has("noktar") and _combo_heard.has("targum"):
				current_phase = Phase.FINAL_CHOICE
		Phase.FINAL_CHOICE:
			# Ending A: Player speaks a spell of Pervorech to restore magic
			current_phase = Phase.FINISHED
			set_physics_process(false)
			GameState.finish_chapter_one("translator")

func _on_silence_updated(silence_sec: float) -> void:
	if current_phase == Phase.FINAL_CHOICE and silence_sec >= 5.0:
		# Ending B: Player stays silent for 5 real seconds -> Price of Silence
		current_phase = Phase.FINISHED
		set_physics_process(false)
		GameState.finish_chapter_one("silence")
