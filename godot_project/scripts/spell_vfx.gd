class_name SpellVFX
extends RefCounted

## Модульные 3D-эффекты заклинаний и безопасный проигрыватель SFX (не падает в --headless).


static func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func play_sfx(parent: Node, path: String, pitch_jitter: float = 0.08, volume_db: float = -3.0) -> void:
	if parent == null or _is_headless() or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(1.0 + randf_range(-pitch_jitter, pitch_jitter), 0.7, 1.4)
	parent.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


static func _make_glow_material(color: Color, energy: float, alpha: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 0.99:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func _spawn_burst_particles(root: Node3D, color: Color, amount: int, speed: float, spread: float = 45.0) -> void:
	if _is_headless():
		return
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.lifetime = 0.75

	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = spread
	pmat.initial_velocity_min = speed * 0.6
	pmat.initial_velocity_max = speed * 1.2
	pmat.gravity = Vector3(0, -2.5, 0)
	pmat.scale_min = 0.6
	pmat.scale_max = 1.4
	particles.process_material = pmat

	var orb := SphereMesh.new()
	orb.radius = 0.065
	orb.height = 0.13
	orb.material = _make_glow_material(color, 3.0)
	particles.draw_pass_1 = orb

	root.add_child(particles)
	particles.emitting = true


static func spawn_virdan_roots(parent: Node, pos: Vector3, strength: float = 1.0) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos

	var mat := _make_glow_material(Color(0.14, 0.95, 0.42), 2.6)
	var spikes := 8
	for i in range(spikes):
		var angle := (TAU / float(spikes)) * float(i)
		var ring_r := 0.75 + 0.15 * float(i % 2)
		var spike := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.02
		cone.bottom_radius = 0.16
		cone.height = 1.45 * clampf(strength, 0.85, 1.6)
		cone.material = mat
		spike.mesh = cone
		spike.position = Vector3(cos(angle) * ring_r, -0.5, sin(angle) * ring_r)
		spike.rotation = Vector3(sin(angle) * 0.28, -angle, -cos(angle) * 0.28)
		root.add_child(spike)

		var tw := root.create_tween()
		tw.tween_property(spike, "position:y", 0.55, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.65)
		tw.tween_property(spike, "scale", Vector3(0.1, 0.05, 0.1), 0.3)

	_spawn_burst_particles(root, Color(0.2, 0.98, 0.48), 18, 3.4, 55.0)
	var cleanup := root.create_tween()
	cleanup.tween_interval(1.25)
	cleanup.tween_callback(root.queue_free)


static func spawn_noktar_wave(parent: Node, pos: Vector3, radius: float = 10.0, is_whisper: bool = false) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos + Vector3(0, 0.12, 0)

	var wave_color := Color(0.36, 0.78, 1.0) if is_whisper else Color(0.62, 0.35, 1.0)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	var mat := _make_glow_material(wave_color, 3.0, 0.85)
	torus.material = mat
	ring.mesh = torus
	ring.scale = Vector3(0.4, 0.35, 0.4)
	root.add_child(ring)

	_spawn_burst_particles(root, wave_color, 16, 2.8, 85.0)

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(radius, 0.25, radius), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	tw.chain().tween_callback(root.queue_free)


static func spawn_melee_slash(parent: Node, pos: Vector3, yaw: float, is_crit: bool = false) -> void:
	if parent == null:
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos + Vector3(0, 0.95, 0)
	root.rotation.y = yaw

	var slash_color := Color(1.0, 0.42, 0.18) if is_crit else Color(0.65, 0.86, 1.0)
	var arc := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.9 if is_crit else 1.45, 0.11, 0.35)
	var mat := _make_glow_material(slash_color, 3.2 if is_crit else 2.2, 0.92)
	box.material = mat
	arc.mesh = box
	arc.position = Vector3(0, 0, -1.25)
	arc.rotation = Vector3(0, 0.7, 0.25)
	root.add_child(arc)

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(arc, "rotation:y", -0.85, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.22)
	tw.chain().tween_callback(root.queue_free)


static func spawn_beam(parent: Node, from_pos: Vector3, to_pos: Vector3, color: Color = Color(1.0, 0.35, 0.22)) -> void:
	if parent == null:
		return
	var diff := to_pos - from_pos
	var dist := diff.length()
	if dist < 0.05:
		return

	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = (from_pos + to_pos) * 0.5

	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.12
	cyl.height = dist
	var mat := _make_glow_material(color, 3.4, 0.95)
	cyl.material = mat
	beam.mesh = cyl
	root.add_child(beam)

	root.look_at(to_pos, Vector3.UP)
	beam.rotation.x = PI * 0.5

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(beam, "scale:x", 0.15, 0.35)
	tw.tween_property(beam, "scale:z", 0.15, 0.35)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(root.queue_free)
