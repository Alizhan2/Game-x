class_name ArcanaPlayer
extends CharacterBody3D

@export var move_speed: float = 6.2
@export var gravity: float = 20.0
@export var spell_radius: float = 12.0
@export var melee_reach: float = 3.2

const MAX_HEALTH := 100
const MELEE_DAMAGE := 12
const MELEE_COOLDOWN := 0.45

@onready var hud_spell_label := get_node_or_null("../CanvasLayer/HudPanel/VBox/SpellLabel") as Label
@onready var hud_status_label := get_node_or_null("../CanvasLayer/HudPanel/VBox/StatusLabel") as Label
@onready var _spawn_position := global_position

var health := MAX_HEALTH
var shield_left := 0.0
var stealth_left := 0.0
var _melee_wait := 0.0
var _attack_requested := false
var _engine_connected := false
var _last_hit := ""
var _shield := MeshInstance3D.new()

func _ready() -> void:
	add_to_group(&"combat_player")
	VoiceReceiver.spell_heard.connect(_on_spell_heard)
	VoiceReceiver.engine_status_changed.connect(_on_engine_status_changed)
	_shield.mesh = SphereMesh.new()
	_shield.scale = Vector3(2.2, 2.2, 2.2)
	var rune := StandardMaterial3D.new()
	rune.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rune.albedo_color = Color(0.96, 0.65, 0.23, 0.32)
	_shield.material_override = rune
	add_child(_shield)
	_update_status()

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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("melee_attack"):
		_attack_requested = true

func _on_engine_status_changed(connected: bool) -> void:
	_engine_connected = connected
	_update_status()

func _update_status() -> void:
	_shield.visible = shield_left > 0.0
	if hud_status_label == null:
		return
	var parts := PackedStringArray(["Голос и клавиши" if _engine_connected else "Клавиши 1/2/3 · Shift — шёпот", "ОЗ %d/%d" % [health, MAX_HEALTH]])
	if shield_left > 0.0:
		parts.append("ЩИТ")
	if stealth_left > 0.0:
		parts.append("СКРЫТНОСТЬ")
	if not _last_hit.is_empty():
		parts.append(_last_hit)
	hud_status_label.text = "  |  ".join(parts)

func _on_spell_heard(spell: String, confidence: float, volume: float, d20: Dictionary, is_whisper: bool) -> void:
	if spell not in ["virdan", "noktar", "targum"]:
		return
	var mode_tag := "ШЁПОТ" if is_whisper else ("КРИК" if volume >= 0.7 else "ГОЛОС")
	var cast_name := "[УДАЛЕНО]" if GameState.ui_censored else spell.to_upper()
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
	var strength: float = d20.get("strength", 1.5 if d20["d20"] == 20 else 1.0)
	stealth_left = 0.0
	_last_hit = ""
	match spell:
		"virdan":
			for guard in _nearby_guards(spell_radius):
				guard.bind_roots((2.5 + volume) * strength)
		"noktar":
			for guard in _nearby_guards(spell_radius):
				guard.expose(6.0 * strength)
			_reveal_nearby()
			if is_whisper:
				stealth_left = 4.0 * strength
		"targum":
			shield_left = maxf(shield_left, (2.5 + volume) * strength)
	_update_status()

func _nearby_guards(radius: float) -> Array[CombatGuard]:
	var nearby: Array[CombatGuard] = []
	for node in get_tree().get_nodes_in_group(&"combat_guards"):
		var guard := node as CombatGuard
		if guard != null and not guard.is_queued_for_deletion() and global_position.distance_squared_to(guard.global_position) <= radius * radius:
			nearby.append(guard)
	return nearby

func _reveal_nearby() -> void:
	# Mark concealed props as noctar_hidden; a closed door panel is a StaticBody3D
	# in noctar_seals, with its mesh and collision shapes underneath it.
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
	else:
		var damage := nearest.receive_strike(MELEE_DAMAGE)
		_last_hit = "Крит −%d" % damage if damage > MELEE_DAMAGE else "Удар −%d" % damage
	_update_status()

func take_hit(amount: int, beam: bool) -> void:
	var attack := "Луч" if beam else "Удар"
	if shield_left > 0.0:
		_last_hit = "%s заблокирован" % attack
	else:
		health = maxi(0, health - amount)
		_last_hit = "%s −%d ОЗ" % [attack, amount]
		if health == 0:
			global_position = _spawn_position
			velocity = Vector3.ZERO
			stealth_left = 0.0
			health = MAX_HEALTH
			_last_hit = "Возвращение к точке старта"
	_update_status()
