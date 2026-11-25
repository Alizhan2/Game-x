extends SceneTree

var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	failed = failed or not condition

func run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var menu = current_scene.get_node("CanvasLayer/TowerMenu")
	check(paused and menu.visible, "Start screen pauses gameplay")
	menu.difficulty.select(2)
	menu.talk.button_pressed = true
	menu.get_node("%Begin").pressed.emit()
	check(not paused and root.get_node("AdaptiveAI").current_difficulty == 2 and root.get_node("VoiceReceiver").push_to_talk_enabled, "Start applies difficulty and push to talk")
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	root.push_input(key)
	check(paused and menu.book.visible and menu.get_node("%Note").text.length() > 4, "Tab shows spellbook and floor note")
	root.push_input(key)
	check(not paused and not menu.visible, "Tab closes spellbook")
	root.get_node("VoiceReceiver").silence_updated.emit(2.4)
	check(is_equal_approx(current_scene.get_node("CanvasLayer/HudPanel/VBox/Silence").value, 2.4), "Silence signal fills HUD")
	var actor = current_scene.get_node("Player")
	var anim = actor.get_node("RenVisual")._animation
	for clip in ["Idle", "Run", "Spell1"]:
		check(anim.has_animation(clip), "Ren animation: " + clip)
	actor._trigger_cast_anim()
	check(anim.current_animation == "Spell1", "Casting drives animation")
	var manager = current_scene.get_node("LevelManager")
	for i in range(1,5):
		manager.load_floor(i)
		await process_frame
		var floor_node = manager._current_floor_node
		check(floor_node.get_node_or_null("SpellGate/WardRunes") != null, "Animated gate on floor %d" % i)
	quit(int(failed))
