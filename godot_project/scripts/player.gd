class_name ArcanaPlayer
extends CharacterBody3D

const _SpellVFX = preload("res://scripts/spell_vfx.gd")

@export var move_speed: float = 6.2
@export var gravity: float = 20.0
@export var spell_radius: float = 12.0
@export var melee_reach: float = 3.2
@export var mouse_sensitivity: float = 0.0032

const MAX_HEALTH := 100
const MELEE_DAMAGE := 12
const MELEE_COOLDOWN := 0.45

@onready var hud_spell_label := get_node_or_null("../CanvasLayer/HudPanel/VBox/SpellLabel") as Label
@onready var hud_health_bar := get_node_or_null("../CanvasLayer/HudPanel/VBox/Health") as ProgressBar
@onready var hud_status_label := get_node_or_null("../CanvasLayer/HudPanel/VBox/StatusLabel") as Label
@onready var _camera_pivot := get_node_or_null("CameraPivot") as Node3D
@onready var _spring_arm := get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
@onready var _camera := find_child("Camera3D", true, false) as Camera3D
@onready var _visual := get_node_or_null("RenVisual")
@onready var _spawn_position := global_position

var health := MAX_HEALTH
var shield_left := 0.0
var stealth_left := 0.0
var _melee_wait := 0.0
var _attack_requested := false
var _engine_connected := false
var _last_hit := ""
var _last_spell_name := ""
var _shield := MeshInstance3D.new()
var _camera_yaw := 0.0
var _camera_pitch := -0.35
var _shake_strength := 0.0


func _ready() -> void:
	add_to_group(&"combat_player")
	VoiceReceiver.spell_heard.connect(_on_spell_heard)
	GameState.censorship_changed.connect(_on_censorship_changed)
	VoiceReceiver.engine_status_changed.connect(_on_engine_status_changed)
	AdaptiveAI.difficulty_changed.connect(func(_diff: int): _update_status())
	AdaptiveAI.counter_shield_changed.connect(func(_spell: String): _update_status())

	if DisplayServer.get_name() != "headless" and _camera_pivot != null:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_camera_pivot.rotation.y = _camera_yaw
	if _spring_arm != null:
		_camera_pitch = _spring_arm.rotation.x

	_shield.mesh = SphereMesh.new()
	_shield.scale = Vector3(2.2, 2.2, 2.2)
	var rune := StandardMaterial3D.new()
	rune.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rune.albedo_color = Color(0.96, 0.65, 0.23, 0.34)
	rune.emission_enabled = true
	rune.emission = Color(0.98, 0.64, 0.16)
	rune.emission_energy_multiplier = 2.4
	_shield.material_override = rune
	add_child(_shield)
	_update_status()


func _add_shake(amount: float) -> void:
	_shake_strength = maxf(_shake_strength, amount)


func _physics_process(delta: float) -> void:
	var was_shielded := shield_left > 0.0
	var was_stealthed := stealth_left > 0.0
	shield_left = maxf(0.0, shield_left - delta)
	stealth_left = maxf(0.0, stealth_left - delta)
	if was_shielded != (shield_left > 0.0) or was_stealthed != (stealth_left > 0.0):
		_update_status()

	_melee_wait = maxf(0.0, _melee_wait - delta)
	if _attack_requested:
		_attack_requested = false
		if _melee_wait == 0.0:
			_melee_attack()

	if _camera != null:
		if _shake_strength > 0.005:
			_camera.h_offset = randf_range(-_shake_strength, _shake_strength)
			_camera.v_offset = randf_range(-_shake_strength, _shake_strength)
			_shake_strength = move_toward(_shake_strength, 0.0, delta * 1.4)
		else:
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0

	if not is_on_floor():
		velocity.y -= gravity * delta
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)
	var basis := Basis(Vector3.UP, _camera_yaw) if _camera_pivot != null else transform.basis
	var direction := (basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	if direction != Vector3.ZERO:
		velocity.x = direction.x * move_speed
		velocity.z = direction.z * move_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed)
		velocity.z = move_toward(velocity.z, 0.0, move_speed)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if DisplayServer.get_name() != "headless" and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			var next_mode := Input.MOUSE_MODE_VISIBLE if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
			Input.set_mouse_mode(next_mode)
			return

	if event is InputEventMouseMotion and _camera_pivot != null:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_camera_yaw -= event.relative.x * mouse_sensitivity
			_camera_pitch = clampf(
				_camera_pitch - event.relative.y * mouse_sensitivity,
				deg_to_rad(-62.0),
				deg_to_rad(22.0)
			)
			_camera_pivot.rotation.y = _camera_yaw
			if _spring_arm != null:
				_spring_arm.rotation.x = _camera_pitch

	if event.is_action_pressed("melee_attack"):
		if DisplayServer.get_name() != "headless" and _camera_pivot != null and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		_attack_requested = true


func _on_engine_status_changed(connected: bool) -> void:
	_engine_connected = connected
	_update_status()


func _update_status() -> void:
	if hud_health_bar != null:
		hud_health_bar.max_value = MAX_HEALTH
		hud_health_bar.value = health
	_shield.visible = shield_left > 0.0
	if hud_status_label == null:
		return
	var parts := PackedStringArray([("Голос по V · клавиши 1/2/3" if VoiceReceiver.push_to_talk_enabled else "Голос и клавиши") if _engine_connected else "Клавиши 1/2/3 · Shift — шёпот · Мышь — камера", "ОЗ %d/%d" % [health, MAX_HEALTH]])
	parts.append("%s (F1–F3)" % AdaptiveAI.get_difficulty_label())
	parts.append("Контр-щит: " + (AdaptiveAI.active_counter_spell.to_upper() if AdaptiveAI.active_counter_spell else "неактивен"))
	if shield_left > 0.0:
		parts.append("ЩИТ")
	if stealth_left > 0.0:
		parts.append("СКРЫТНОСТЬ")
	if not _last_hit.is_empty():
		parts.append(_last_hit)
	hud_status_label.text = "  |  ".join(parts)


func _trigger_cast_anim() -> void:
	if _visual != null and _visual.has_method("play_action"):
		_visual.play_action([&"Spell1", &"Spellcast_Shoot", &"Cast", &"Spell_Cast"], 0.45)


func _on_censorship_changed(enabled: bool) -> void:
	if hud_spell_label == null or _last_spell_name.is_empty():
		return
	var label := hud_spell_label.text
	if enabled:
		hud_spell_label.text = label.replace(_last_spell_name, "[УДАЛЕНО]")
	else:
		hud_spell_label.text = label.replace("[УДАЛЕНО]", _last_spell_name)


func _on_spell_heard(spell: String, confidence: float, volume: float, d20: Dictionary, is_whisper: bool) -> void:
	if spell not in ["virdan", "noktar", "targum"]:
		return
	var mode_tag := "ШЁПОТ" if is_whisper else ("КРИК" if volume >= 0.7 else "ГОЛОС")
	_last_spell_name = spell.to_upper()
	var cast_name := "[УДАЛЕНО]" if GameState.ui_censored else _last_spell_name
	if hud_spell_label != null:
		hud_spell_label.modulate = Color.WHITE
		if d20["d20"] == 1:
			hud_spell_label.modulate = Color("ff9696")
		elif d20["d20"] == 20:
			hud_spell_label.modulate = Color("ffdc7a")
		hud_spell_label.text = "%s (%d%% · %s) | d20: %d (+%d) = %d (%s)" % [
			cast_name, roundi(confidence * 100.0), mode_tag, d20["d20"], d20["bonus"], d20["total"], d20["tier"]
		]
	if d20["d20"] == 1:
		return
	if d20.get("countered", false) and not _nearby_guards(spell_radius).is_empty():
		_last_hit = "Заклинание отражено"
		_update_status()
		return

	var strength: float = d20.get("strength", 1.5 if d20["d20"] == 20 else 1.0)
	stealth_left = 0.0
	_last_hit = ""
	var fx_parent := get_parent() if get_parent() != null else self

	match spell:
		"virdan":
			var targets := _nearby_guards(spell_radius)
			for guard in targets:
				guard.bind_roots((2.5 + volume) * strength)
			if targets.is_empty():
				var forward := -Basis(Vector3.UP, _camera_yaw).z
				_SpellVFX.spawn_virdan_roots(fx_parent, global_position + forward * 3.0, strength)
			_SpellVFX.play_sfx(self, "res://assets/audio/spells/virdan.ogg")
			_trigger_cast_anim()
			_add_shake(0.14)
		"noktar":
			for guard in _nearby_guards(spell_radius):
				guard.expose(6.0 * strength)
			_reveal_nearby()
			if is_whisper:
				stealth_left = 4.0 * strength
			_SpellVFX.spawn_noktar_wave(fx_parent, global_position, spell_radius, is_whisper)
			_SpellVFX.play_sfx(self, "res://assets/audio/spells/noktar.ogg")
			_trigger_cast_anim()
		"targum":
			_SpellVFX.spawn_shield_sparks(self)
			shield_left = maxf(shield_left, (2.5 + volume) * strength)
			_SpellVFX.play_sfx(self, "res://assets/audio/spells/targum.ogg")
			_trigger_cast_anim()
			_add_shake(0.16)
	_update_status()


func _nearby_guards(radius: float) -> Array[CombatGuard]:
	var nearby: Array[CombatGuard] = []
	for node in get_tree().get_nodes_in_group(&"combat_guards"):
		var guard := node as CombatGuard
		if guard != null and not guard.is_queued_for_deletion() and global_position.distance_squared_to(guard.global_position) <= radius * radius:
			nearby.append(guard)
	return nearby


func _reveal_nearby() -> void:
	for node in get_tree().get_nodes_in_group(&"noctar_hidden"):
		var prop := node as Node3D
		if prop != null and global_position.distance_to(prop.global_position) <= spell_radius:
			prop.show()
	for node in get_tree().get_nodes_in_group(&"noctar_seals"):
		var seal := node as StaticBody3D
		if seal != null and global_position.distance_to(seal.global_position) <= spell_radius:
			seal.hide()
			seal.collision_layer = 0
			seal.collision_mask = 0


func _melee_attack() -> void:
	_melee_wait = MELEE_COOLDOWN
	stealth_left = 0.0
	var fx_parent := get_parent() if get_parent() != null else self
	var slash_yaw: float = _visual.rotation.y + PI if _visual != null else _camera_yaw
	if _visual != null and _visual.has_method("play_action"):
		_visual.play_action([&"1H_Melee_Attack_Slice_Diagonal", &"Attack", &"Melee", &"Staff_Attack"], 0.35)
	_SpellVFX.play_sfx(self, "res://assets/audio/kenney_rpg/chop.ogg")

	var nearest: CombatGuard
	var best_distance := INF
	for guard in _nearby_guards(melee_reach):
		var distance := global_position.distance_squared_to(guard.global_position)
		if distance >= best_distance:
			continue
		var sight := PhysicsRayQueryParameters3D.create(global_position, guard.global_position)
		sight.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(sight)
		var obstacle := hit.get("collider") as Node
		if obstacle != null and obstacle != guard and not guard.is_ancestor_of(obstacle):
			continue
		nearest = guard
		best_distance = distance

	if nearest == null:
		_last_hit = "Удар мимо"
		_SpellVFX.spawn_melee_slash(fx_parent, global_position, slash_yaw, false)
	else:
		var damage := nearest.receive_strike(MELEE_DAMAGE)
		var is_crit := damage > MELEE_DAMAGE
		_last_hit = "Крит −%d" % damage if is_crit else "Удар −%d" % damage
		if damage == 0:
			_last_hit = "Тень неуязвима. Примени Ноктар (2)." if nearest.requires_exposure else "Щит поглотил удар"
		_SpellVFX.spawn_melee_slash(fx_parent, global_position, slash_yaw, is_crit)
		_add_shake(0.22 if is_crit else 0.10)
	_update_status()


func set_floor_spawn(point: Vector3) -> void:
	_spawn_position = point
	global_position = point
	velocity = Vector3.ZERO
	reset_physics_interpolation()


func take_hit(amount: int, beam: bool) -> bool:
	var took_damage := shield_left <= 0.0
	var attack := "Луч" if beam else "Удар"
	if not took_damage:
		_last_hit = "%s заблокирован" % attack
		_add_shake(0.12)
	else:
		health = maxi(0, health - amount)
		_last_hit = "%s −%d ОЗ" % [attack, amount]
		_add_shake(0.24)
		if _visual != null and _visual.has_method("play_action"):
			_visual.play_action([&"RecieveHit", &"Hit_A", &"Hit"], 0.35)
		if health == 0:
			set_floor_spawn(_spawn_position)
			stealth_left = 0.0
			health = MAX_HEALTH
			_last_hit = "Возвращение к точке старта"
	_update_status()
	return took_damage
