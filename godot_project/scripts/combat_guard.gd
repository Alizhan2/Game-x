class_name CombatGuard
extends Node3D

const _SpellVFX = preload("res://scripts/spell_vfx.gd")

## Боевой страж: преследует игрока, телеграфирует атаку, реагирует на корни/уязвимость и проигрывает анимации.
@export var max_health: int = 60
@export var approach_speed: float = 1.8
@export var detection_radius: float = 12.0
@export var requires_exposure := false

signal beam_blocked(player: ArcanaPlayer)

const STRIKE_RANGE := 2.8
const BEAM_RANGE := 8.0
const WINDUP := 1.2
const RECOVERY := 2.0

@onready var health: int = max_health
var rooted_for := 0.0
var exposed_for := 0.0
var _recovery := RECOVERY
var _windup := 0.0
var _casting_beam := false
var _status := Label3D.new()
var _telegraph_ring := MeshInstance3D.new()
var _animation: AnimationPlayer = null
var _action_until_msec := 0


func _ready() -> void:
	add_to_group(&"combat_guards")
	# Стартовая тестовая арена может не иметь 3D-модели; авторские модели сохраняются.
	if find_children("*", "MeshInstance3D", true, false).is_empty():
		var body := MeshInstance3D.new()
		body.mesh = PrismMesh.new()
		body.scale = Vector3(1.2, 1.8, 1.2)
		add_child(body)

	_animation = find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation != null:
		for loop_clip: StringName in [&"Idle", &"Running_A", &"Walk", &"CharacterArmature|Idle", &"CharacterArmature|Run"]:
			if _animation.has_animation(loop_clip):
				_animation.get_animation(loop_clip).loop_mode = Animation.LOOP_LINEAR

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.95
	ring_mesh.outer_radius = 1.15
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.25, 0.18, 0.85)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.22, 0.14)
	ring_mat.emission_energy_multiplier = 2.8
	ring_mesh.material = ring_mat
	_telegraph_ring.mesh = ring_mesh
	_telegraph_ring.position.y = 0.06
	_telegraph_ring.scale = Vector3(1.0, 0.3, 1.0)
	_telegraph_ring.visible = false
	add_child(_telegraph_ring)

	_status.position.y = 2.2
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.font_size = 38
	add_child(_status)
	_update_status()


func _play_clip(candidates: Array, lock_sec: float = 0.0) -> void:
	if _animation == null:
		return
	if lock_sec <= 0.0 and Time.get_ticks_msec() < _action_until_msec:
		return
	for clip in candidates:
		if _animation.has_animation(clip):
			if lock_sec > 0.0 or _animation.current_animation != clip:
				_animation.play(clip, 0.1)
			if lock_sec > 0.0:
				_action_until_msec = Time.get_ticks_msec() + int(lock_sec * 1000.0)
			return


func expose(duration: float) -> void:
	exposed_for = maxf(exposed_for, duration)
	_update_status()


func bind_roots(duration: float) -> void:
	rooted_for = maxf(rooted_for, duration)
	_windup = 0.0
	_recovery = RECOVERY
	if get_parent() != null:
		_SpellVFX.spawn_virdan_roots(get_parent(), global_position, 1.0)
	_update_status()


func receive_strike(base_damage: int) -> int:
	if requires_exposure and exposed_for <= 0.0:
		return 0
	var damage := base_damage * 2 if exposed_for > 0.0 else base_damage
	exposed_for = 0.0
	health = maxi(0, health - damage)
	_play_clip([&"RecieveHit", &"Hit_A", &"Hit"], 0.35)
	if health == 0:
		_on_defeated()
	_update_status()
	return damage


func _on_defeated() -> void:
	queue_free()


func _physics_process(delta: float) -> void:
	if is_queued_for_deletion():
		return
	exposed_for = maxf(0.0, exposed_for - delta)
	rooted_for = maxf(0.0, rooted_for - delta)
	_recovery = maxf(0.0, _recovery - delta)
	var player := get_tree().get_first_node_in_group(&"combat_player") as ArcanaPlayer
	var moving := false
	if player != null and rooted_for <= 0.0:
		moving = _track_player(player, delta)
	if _windup <= 0.0:
		_play_clip([&"Running_A", &"Walk", &"CharacterArmature|Run"] if moving else [&"Idle", &"CharacterArmature|Idle"])
	_update_status()


func _should_cast_beam(distance: float) -> bool:
	return distance > STRIKE_RANGE


func _track_player(player: ArcanaPlayer, delta: float) -> bool:
	var offset := player.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if player.stealth_left > 0.0 or distance > detection_radius:
		_windup = 0.0
		return false
	# Стражи не видят и не бьют сквозь закрытые двери.
	var sight := PhysicsRayQueryParameters3D.create(global_position, player.global_position)
	sight.exclude = [player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
		_windup = 0.0
		return false

	if offset.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(offset.x, offset.z), minf(delta * 8.0, 1.0))

	if _windup > 0.0:
		_windup = maxf(0.0, _windup - delta)
		if _windup == 0.0:
			var reach := BEAM_RANGE if _casting_beam else STRIKE_RANGE
			var took_damage := false
			if _casting_beam and get_parent() != null:
				_SpellVFX.spawn_beam(
					get_parent(),
					global_position + Vector3(0, 1.3, 0),
					player.global_position + Vector3(0, 0.9, 0)
				)
			if distance <= reach:
				var base_damage := 14 if _casting_beam else 9
				var damage := maxi(1, roundi(base_damage * AdaptiveAI.get_damage_multiplier()))
				took_damage = player.take_hit(damage, _casting_beam)
				if _casting_beam and not took_damage:
					beam_blocked.emit(player)
			AdaptiveAI.record_player_hit(took_damage)
			_recovery = RECOVERY
		return false
	elif _recovery == 0.0 and distance <= BEAM_RANGE:
		_casting_beam = _should_cast_beam(distance)
		_windup = WINDUP
		_play_clip(
			[&"Spell1", &"Sword_Attack2", &"Spellcast_Shoot", &"Cast", &"CharacterArmature|Shoot"] if _casting_beam else [&"Sword_Attack", &"Staff_Attack", &"1H_Melee_Attack_Slice_Diagonal", &"Attack", &"CharacterArmature|Attack"],
			0.55
		)
		return false
	elif distance > STRIKE_RANGE * 0.8:
		global_position += offset.normalized() * minf(approach_speed * delta, distance - STRIKE_RANGE * 0.8)
		return true
	return false


func _update_status() -> void:
	_telegraph_ring.visible = _windup > 0.0
	if _telegraph_ring.visible:
		var pulse := 1.0 + 0.18 * sin(float(Time.get_ticks_msec()) * 0.015)
		_telegraph_ring.scale = Vector3(pulse, 0.3, pulse)

	var tags := PackedStringArray()
	if rooted_for > 0.0:
		tags.append("КОРНИ")
	if exposed_for > 0.0:
		tags.append("УЯЗВИМОСТЬ")
	elif requires_exposure:
		tags.append("ТЕНЬ · НОКТАР")
	if _windup > 0.0:
		tags.append("ГОТОВИТ ЛУЧ" if _casting_beam else "ЗАМАХ")
	_status.text = "%d / %d  %s" % [health, max_health, " · ".join(tags)]
	if exposed_for > 0.0:
		_status.modulate = Color("d7a4ff")
	elif rooted_for > 0.0:
		_status.modulate = Color("86efa4")
	elif _windup > 0.0:
		_status.modulate = Color("ff8b80")
	else:
		_status.modulate = Color.WHITE
