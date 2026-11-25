extends CharacterBody3D

@export var move_speed: float = 6.2
@export var gravity: float = 20.0

@onready var hud_spell_label: Label = $"../CanvasLayer/HudPanel/VBox/SpellLabel"
@onready var hud_status_label: Label = $"../CanvasLayer/HudPanel/VBox/StatusLabel"

func _ready() -> void:
	VoiceReceiver.spell_heard.connect(_on_spell_heard)
	VoiceReceiver.engine_status_changed.connect(_on_engine_status_changed)
	_on_engine_status_changed(false)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)

	move_and_slide()

func _on_engine_status_changed(connected: bool) -> void:
	if hud_status_label == null:
		return
	if connected:
		hud_status_label.text = "🎙️ ИИ-модель ONNX активна (127.0.0.1:5055) | Клавиши 1/2/3 тоже работают"
	else:
		hud_status_label.text = "⌨️ Микрофон не подключён — активен режим [1] Вирдан | [2] Ноктар | [3] Таргум (Shift = шёпот)"

func _on_spell_heard(spell: String, confidence: float, volume: float, d20: Dictionary, is_whisper: bool) -> void:
	var mode_tag := "ШЁПОТ" if is_whisper else "КРИК"
	if hud_spell_label != null:
		if GameState.ui_censored:
			hud_spell_label.text = "[УДАЛЕНО] | d20: %d (+%d) = %d (%s)" % [d20["d20"], d20["bonus"], d20["total"], d20["tier"]]
		else:
			hud_spell_label.text = "✨ %s (%d%% • %s) | d20: %d (+%d) = %d (%s)" % [
				spell.to_upper(), int(round(confidence * 100.0)), mode_tag,
				d20["d20"], d20["bonus"], d20["total"], d20["tier"]
			]

	match spell:
		"virdan":
			_cast_virdan(volume)
		"noktar":
			_cast_noktar(is_whisper)
		"targum":
			_cast_targum(volume)

func _cast_virdan(volume: float) -> void:
	# TODO (48h Jam): Spawn emerald roots binding nearby enemies; duration scales with volume.
	pass

func _cast_noktar(is_whisper: bool) -> void:
	# TODO (48h Jam): Spawn spectral spirit; passes grates silently when is_whisper == true.
	pass

func _cast_targum(volume: float) -> void:
	# TODO (48h Jam): Spawn geometric stone shield blocking Archive-0 beams.
	pass
