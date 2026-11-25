class_name CombatGuard
extends Node3D

## Place this script on an ordinary guard, or extend it for a story encounter.
@export var max_health: int = 60
@export var approach_speed: float = 1.8
@export var detection_radius: float = 12.0

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

func _ready() -> void:
	add_to_group(&"combat_guards")
	# The starter arena has an empty Keeper node. Authored models take precedence.
	if find_children("*", "MeshInstance3D", true, false).is_empty():
		var body := MeshInstance3D.new()
		body.mesh = PrismMesh.new()
		body.scale = Vector3(1.2, 1.8, 1.2)
		add_child(body)
	_status.position.y = 1.45
	_status.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status.font_size = 38
	add_child(_status)
	_update_status()

func expose(duration: float) -> void:
	exposed_for = maxf(exposed_for, duration)
	_update_status()

func bind_roots(duration: float) -> void:
	rooted_for = maxf(rooted_for, duration)
	_windup = 0.0
	_recovery = RECOVERY
	_update_status()

func receive_strike(base_damage: int) -> int:
	var damage := base_damage * 2 if exposed_for > 0.0 else base_damage
	exposed_for = 0.0
	health = maxi(0, health - damage)
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
	if player != null and rooted_for <= 0.0:
		_track_player(player, delta)
	_update_status()

func _track_player(player: ArcanaPlayer, delta: float) -> void:
	var offset := player.global_position - global_position
	offset.y = 0.0
	var distance := offset.length()
	if player.stealth_left > 0.0 or distance > detection_radius:
		_windup = 0.0
		return
	# Arena guards cannot see or hit through closed passages.
	var sight := PhysicsRayQueryParameters3D.create(global_position, player.global_position)
	sight.exclude = [player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
		_windup = 0.0
		return
	if _windup > 0.0:
		_windup = maxf(0.0, _windup - delta)
		if _windup == 0.0:
			var reach := BEAM_RANGE if _casting_beam else STRIKE_RANGE
			var took_damage := false
			if distance <= reach:
				var base_damage := 14 if _casting_beam else 9
				var damage := maxi(1, roundi(base_damage * AdaptiveAI.get_damage_multiplier()))
				took_damage = player.take_hit(damage, _casting_beam)
			AdaptiveAI.record_player_hit(took_damage)
			_recovery = RECOVERY
	elif _recovery == 0.0 and distance <= BEAM_RANGE:
		_casting_beam = distance > STRIKE_RANGE
		_windup = WINDUP
	elif distance > STRIKE_RANGE * 0.8:
		global_position += offset.normalized() * minf(approach_speed * delta, distance - STRIKE_RANGE * 0.8)

func _update_status() -> void:
	var tags := PackedStringArray()
	if rooted_for > 0.0:
		tags.append("КОРНИ")
	if exposed_for > 0.0:
		tags.append("УЯЗВИМОСТЬ")
	if _windup > 0.0:
		tags.append("ГОТОВИТ ЛУЧ" if _casting_beam else "ЗАМАХ")
	_status.text = "%d / %d  %s" % [health, max_health, " · ".join(tags)]
	if exposed_for > 0.0:
		_status.modulate = Color("d7a4ff")
	elif rooted_for > 0.0:
		_status.modulate = Color("86efa4")
	else:
		_status.modulate = Color.WHITE
