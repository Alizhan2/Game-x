extends Node3D

const IDLE: StringName = &"Idle"
const RUN: StringName = &"Running_A"

@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var _animation: AnimationPlayer = find_child("AnimationPlayer", true, false) as AnimationPlayer

var _action_until_msec: int = 0


func _ready() -> void:
	if _animation != null:
		for clip: StringName in [IDLE, RUN]:
			if _animation.has_animation(clip):
				_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func play_action(candidates: Array, duration: float = 0.45) -> void:
	if _animation == null:
		return
	for clip in candidates:
		if _animation.has_animation(clip):
			_animation.play(clip, 0.08)
			_action_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)
			return


func _process(delta: float) -> void:
	var movement := Vector2(_player.velocity.x, _player.velocity.z)
	if movement.length_squared() > 0.04:
		rotation.y = lerp_angle(rotation.y, atan2(movement.x, movement.y), minf(delta * 14.0, 1.0))

	if Time.get_ticks_msec() < _action_until_msec:
		return

	var clip := RUN if movement.length_squared() > 0.04 else IDLE
	if _animation != null and _animation.current_animation != clip and _animation.has_animation(clip):
		_animation.play(clip, 0.12)
