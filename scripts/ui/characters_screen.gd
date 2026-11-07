extends ScreenBase
## Pantalla PERSONAJES: elige la ficha con la que juegas. La elección se guarda al tocar.

var _group := ButtonGroup.new()
var _buttons: Dictionary = {}

@onready var _preview: CharacterPreview = %Preview


func _ready() -> void:
	for entry in CharacterCatalog.all_characters():
		var character: Dictionary = entry
		var character_id: String = str(character["id"])
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = _group
		button.custom_minimum_size = Vector2(0, 100)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = str(character["name"])
		button.icon = UiTheme.dot_icon(character["color"])
		button.add_theme_constant_override("h_separation", 24)
		button.pressed.connect(_on_character_pressed.bind(character_id))
		%CharacterList.add_child(button)
		_buttons[character_id] = button
	%PlayButton.pressed.connect(_on_play_pressed)

	GameState.ensure_valid_selection()
	_show(GameState.selected_character_id)
	UiFx.fade_scale_in([%ListPanel, %DetailPanel], 0.1, 0.45)


func _on_character_pressed(character_id: String) -> void:
	GameState.select_character(character_id)
	_show(character_id)


func _show(character_id: String) -> void:
	var character: Dictionary = CharacterCatalog.find_character(character_id)
	if character.is_empty():
		return
	if _buttons.has(character_id):
		(_buttons[character_id] as Button).set_pressed_no_signal(true)
	%NameLabel.text = str(character["name"])
	%RoleLabel.text = str(character["title"])
	%DescLabel.text = str(character["description"])
	%RefLabel.text = "Lectura: %s" % str(character["reference"])
	_preview.show_character(character)


func _on_play_pressed() -> void:
	GameState.ensure_valid_selection()
	SceneRouter.go_to("board")
