extends Node

signal spell_heard(spell: String, confidence: float, volume: float, d20_result: Dictionary, is_whisper: bool)
signal silence_updated(silence_sec: float)
signal engine_status_changed(connected: bool)

const UDP_PORT: int = 5055
const CAST_COOLDOWN: float = 0.85
const MIN_CONFIDENCE: float = 0.72

var push_to_talk_enabled: bool = false
var _udp := PacketPeerUDP.new()
var _engine_pid: int = -1
var _connected: bool = false
var _last_packet_msec: int = 0
var _next_cast_msec: int = 0
var _voice_silence_sec: float = 0.0
var _keyboard_silence_sec: float = 0.0
var _reported_silence_sec: float = 0.0

func _ready() -> void:
	var err := _udp.bind(UDP_PORT, "127.0.0.1")
	if err != OK:
		push_warning("VoiceReceiver: UDP bind failed on port %d; keyboard fallback [1/2/3] active." % UDP_PORT)
	_try_launch_bundled_voice_engine()

func _try_launch_bundled_voice_engine() -> void:
	if OS.has_feature("editor"):
		return
	var exe_dir := OS.get_executable_path().get_base_dir()
	var voice_exe := exe_dir.path_join("voice_engine.exe")
	if FileAccess.file_exists(voice_exe):
		_engine_pid = OS.create_process(voice_exe, ["--skip-calibration"])

func _exit_tree() -> void:
	_udp.close()
	if _engine_pid > 0:
		OS.kill(_engine_pid)

func _process(delta: float) -> void:
	_poll_udp()
	_handle_keyboard_fallback(delta)

	var now := Time.get_ticks_msec()
	if _connected and now - _last_packet_msec > 3000:
		_connected = false
		_voice_silence_sec = 0.0
		engine_status_changed.emit(false)

	# A held 0 measures a continuous keyboard attempt, even if voice packets arrive.
	var silence_sec := _keyboard_silence_sec if _keyboard_silence_sec > 0.0 else _voice_silence_sec
	if silence_sec != _reported_silence_sec:
		_reported_silence_sec = silence_sec
		silence_updated.emit(silence_sec)

func _poll_udp() -> void:
	while _udp.get_available_packet_count() > 0:
		var raw := _udp.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue

		_last_packet_msec = Time.get_ticks_msec()
		if not _connected:
			_connected = true
			engine_status_changed.emit(true)

		var spell: String = str(parsed.get("spell", "background"))
		var conf: float = float(parsed.get("confidence", 0.0))
		var vol: float = float(parsed.get("volume", 0.0))
		_voice_silence_sec = float(parsed.get("silence_sec", 0.0))

		if spell != "background" and conf >= MIN_CONFIDENCE:
			if not push_to_talk_enabled or Input.is_action_pressed("push_to_talk"):
				_emit_spell_if_ready(spell, conf, vol)

func _handle_keyboard_fallback(delta: float) -> void:
	var whisper := Input.is_key_pressed(KEY_SHIFT)
	var fallback_vol := 0.2 if whisper else 0.85

	if Input.is_action_just_pressed("spell_virdan"):
		_emit_spell_if_ready("virdan", 1.0, fallback_vol)
	elif Input.is_action_just_pressed("spell_noktar"):
		_emit_spell_if_ready("noktar", 1.0, fallback_vol)
	elif Input.is_action_just_pressed("spell_targum"):
		_emit_spell_if_ready("targum", 1.0, fallback_vol)

	if Input.is_action_pressed("silence_hold"):
		_keyboard_silence_sec += delta
	else:
		_keyboard_silence_sec = 0.0

func _emit_spell_if_ready(spell: String, confidence: float, volume: float) -> void:
	var now := Time.get_ticks_msec()
	if now < _next_cast_msec:
		return
	_next_cast_msec = now + int(CAST_COOLDOWN * 1000.0)
	var is_whisper := volume < 0.28
	var d20_result := D20Roller.roll_spell(confidence, volume)
	spell_heard.emit(spell, confidence, volume, d20_result, is_whisper)
