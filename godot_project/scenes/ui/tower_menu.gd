extends ColorRect

@onready var setup: VBoxContainer = %Setup
@onready var book: VBoxContainer = %Book
@onready var difficulty: OptionButton = %Difficulty
@onready var talk: CheckButton = %PushToTalk
@onready var hud: PanelContainer = get_node("../HudPanel")

const NOTES := [
	"Я оставила печать в сундуке справа от кафедры. Раскрой книгу Ноктаром, и знак укажет путь.",
	"Эльфы не ломали решётку. Они вплетали корни прямо в её прутья.",
	"Память слышит шёпот. Произнеси Ноктар у решётки тихо или нажми Shift + 2.",
	"Архив выучит слово, если повторять его раз за разом. Чередуй школы и следи за контрщитом."
]
var previous_mouse_mode := Input.MOUSE_MODE_CAPTURED

func _ready() -> void:
	difficulty.add_item("Ученик", AdaptiveAI.Difficulty.APPRENTICE)
	difficulty.add_item("Маг", AdaptiveAI.Difficulty.MAGE)
	difficulty.add_item("Архимаг", AdaptiveAI.Difficulty.ARCHMAGE)
	difficulty.select(int(AdaptiveAI.current_difficulty))
	talk.button_pressed = VoiceReceiver.push_to_talk_enabled
	%Begin.pressed.connect(_begin)
	%CloseBook.pressed.connect(_resume)
	_open()
	%Begin.grab_focus()

func _begin() -> void:
	AdaptiveAI.set_difficulty(difficulty.get_selected_id() as AdaptiveAI.Difficulty)
	VoiceReceiver.push_to_talk_enabled = talk.button_pressed
	get_node("../../Player")._update_status()
	setup.hide()
	_resume()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if setup.visible or (event.keycode != KEY_TAB and not (visible and event.keycode == KEY_ESCAPE)):
		return
	get_viewport().set_input_as_handled()
	if visible:
		_resume()
	else:
		%Note.text = NOTES[clampi(GameState.current_floor - 1, 0, NOTES.size() - 1)]
		book.show()
		_open()
		%CloseBook.grab_focus()

func _open() -> void:
	previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.hide()
	show()
	get_tree().paused = true

func _resume() -> void:
	hide()
	book.hide()
	hud.show()
	get_tree().paused = false
	Input.mouse_mode = previous_mouse_mode

func _exit_tree() -> void:
	if visible and is_inside_tree():
		get_tree().paused = false
