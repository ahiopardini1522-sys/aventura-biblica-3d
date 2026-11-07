class_name ChallengePanel
extends Control
## Panel de los desafíos bíblicos. Muestra el tipo de desafío, la pregunta (o las pistas de
## "¿Quién soy?"), las opciones, y al responder: si acertó, la respuesta correcta, la
## explicación y la referencia bíblica. No decide premios ni castigos: eso lo hace GameFlow,
## que le pasa el resultado con show_outcome().

signal answered(index: int)
signal continued
signal closed

const TYPE_COLORS := {
	"multiple_choice": Color(0.50, 0.74, 1.0),
	"true_false": Color(0.98, 0.72, 0.38),
	"character": Color(0.80, 0.62, 1.0),
	"complete_verse": Color(1.0, 0.88, 0.50),
	"event": Color(0.45, 0.88, 0.80),
}
const LETTERS: Array[String] = ["A", "B", "C", "D"]
const GOOD_BG := Color(0.13, 0.46, 0.26)
const GOOD_EDGE := Color(0.55, 0.95, 0.62)
const BAD_BG := Color(0.55, 0.18, 0.17)
const BAD_EDGE := Color(1.0, 0.55, 0.45)
const GOOD_TEXT := Color(0.58, 0.96, 0.64)
const BAD_TEXT := Color(1.0, 0.62, 0.52)

var challenge: Challenge
var selected: int = -1

var _answered: bool = false
var _buttons: Array[Button] = []
var _show_tween: Tween
var _feedback_tween: Tween
var _option_tweens: Array[Tween] = []


func _ready() -> void:
	%ContinueButton.pressed.connect(_on_continue_pressed)
	%RightPanel.add_theme_stylebox_override("panel",
			UiTheme.box(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.12), 28, 2, 28.0, 24.0, false))


## Muestra un desafío. "win_text" y "lose_text" explican qué se juega el jugador.
func present(item: Challenge, player_name: String, player_color: Color,
		win_text: String = "", lose_text: String = "") -> void:
	challenge = item
	selected = -1
	_answered = false
	var accent: Color = TYPE_COLORS.get(item.type, UiTheme.GOLD)

	%Card.add_theme_stylebox_override("panel",
			UiTheme.box(Color(0.05, 0.08, 0.17, 0.95), Color(accent, 0.95), 36, 4, 40.0, 30.0, true))
	%TypeLabel.text = item.title()
	%TypeLabel.add_theme_color_override("font_color", accent.lightened(0.25))
	_build_difficulty(item.difficulty, accent)

	var prompt: String = item.prompt
	if item.type == Challenge.TYPE_CHARACTER and prompt.strip_edges().is_empty():
		prompt = "¿Quién soy?"
	%PromptLabel.text = prompt
	_build_clues(item)
	_build_options(item)
	%NoteLabel.visible = item.type == Challenge.TYPE_COMPLETE_VERSE

	%PlayerName.text = player_name
	%PlayerDot.add_theme_stylebox_override("panel",
			UiTheme.box(player_color, Color(1, 1, 1, 0.92), 30, 3, 0.0, 0.0, false))
	%WinLabel.text = win_text
	%LoseLabel.text = lose_text
	%WinLabel.visible = not win_text.is_empty()
	%LoseLabel.visible = not lose_text.is_empty()
	%StakesBox.visible = true
	%FeedbackBox.visible = false
	%ContinueButton.visible = false
	%OutcomeLabel.text = ""

	if _show_tween != null and _show_tween.is_valid():
		_show_tween.kill()
	visible = true
	%Dim.modulate.a = 0.0
	%Card.modulate.a = 0.0
	_show_tween = create_tween()
	_show_tween.tween_property(%Dim, "modulate:a", 1.0, 0.2)
	_start_card_pop.call_deferred()
	_fade_in_options()


func is_open() -> bool:
	return visible


func is_answered() -> bool:
	return _answered


func option_count() -> int:
	return _buttons.size()


func option_text(index: int) -> String:
	return _buttons[index].text if index >= 0 and index < _buttons.size() else ""


func prompt_text() -> String:
	return (%PromptLabel as Label).text


func clue_count() -> int:
	return (%CluesBox as Control).get_child_count() if (%CluesBox as Control).visible else 0


func result_text() -> String:
	return (%ResultLabel as Label).text


func answer_text() -> String:
	return (%AnswerLabel as Label).text


func explanation_text() -> String:
	return (%ExplanationLabel as Label).text


func reference_text() -> String:
	return (%ReferenceLabel as Label).text


func outcome_text() -> String:
	return (%OutcomeLabel as Label).text


func feedback_visible() -> bool:
	return (%FeedbackBox as Control).visible


func continue_visible() -> bool:
	return (%ContinueButton as Control).visible


func continue_pressed() -> void:
	_on_continue_pressed()


## Responde como si se tocara esa opción (lo usan las pruebas automáticas).
## Devuelve false si el panel no está esperando una respuesta o la opción no existe.
func choose(index: int) -> bool:
	if not visible or challenge == null or _answered or index < 0 or index >= _buttons.size():
		return false
	_on_option_pressed(index)
	return true


## Escribe qué ganó o perdió el jugador (por ejemplo, "+1 estrella · avanzas 2 casillas").
func show_outcome(text: String, positive: bool) -> void:
	%OutcomeLabel.text = text
	%OutcomeLabel.add_theme_color_override("font_color", GOOD_TEXT if positive else BAD_TEXT)


## Cierra el panel con un fundido y avisa con "closed".
func close() -> void:
	if not visible:
		closed.emit()
		return
	if _show_tween != null and _show_tween.is_valid():
		_show_tween.kill()
	_show_tween = create_tween().set_parallel(true)
	_show_tween.tween_property(%Card, "modulate:a", 0.0, 0.18)
	_show_tween.tween_property(%Dim, "modulate:a", 0.0, 0.22)
	_show_tween.chain().tween_callback(_finish_close)


func _finish_close() -> void:
	visible = false
	closed.emit()


## Las opciones aparecen una tras otra, con un pequeño retraso entre cada una.
func _fade_in_options() -> void:
	_clear_option_tweens()
	for i in _buttons.size():
		var button: Button = _buttons[i]
		button.modulate.a = 0.0
		var tween: Tween = button.create_tween()
		tween.tween_property(button, "modulate:a", 1.0, 0.3).set_delay(0.06 * float(i))
		_option_tweens.append(tween)


func _clear_option_tweens() -> void:
	for tween in _option_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_option_tweens.clear()


func _start_card_pop() -> void:
	if not is_inside_tree():
		return
	var card := %Card as Control
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.9, 0.9)
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.18)
	tween.tween_property(card, "scale", Vector2.ONE, 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build_difficulty(level: int, accent: Color) -> void:
	for child in %DifficultyBox.get_children():
		%DifficultyBox.remove_child(child)
		child.queue_free()
	for i in Challenge.MAX_DIFFICULTY:
		%DifficultyBox.add_child(StarIcon.new().configure(accent.lightened(0.2), i < level, 36.0))


func _build_clues(item: Challenge) -> void:
	var box := %CluesBox as VBoxContainer
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	box.visible = item.type == Challenge.TYPE_CHARACTER
	if not box.visible:
		return
	for i in item.clues.size():
		var line := Label.new()
		line.text = "Pista %d:  %s" % [i + 1, item.clues[i]]
		line.add_theme_font_size_override("font_size", 34)
		line.add_theme_color_override("font_color", Color(0.93, 0.92, 0.98))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(line)


func _build_options(item: Challenge) -> void:
	var box := %Options as VBoxContainer
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	_buttons.clear()
	var two_choices: bool = item.type == Challenge.TYPE_TRUE_FALSE
	for i in item.options.size():
		var button := Button.new()
		button.name = "Option%d" % i
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER if two_choices else HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0.0, 132.0 if two_choices else 100.0)
		button.add_theme_font_size_override("font_size", 54 if two_choices else 38)
		if two_choices:
			button.text = item.options[i].to_upper()
		else:
			button.text = "%s   %s" % [LETTERS[i], item.options[i]]
		button.pressed.connect(_on_option_pressed.bind(i))
		box.add_child(button)
		_buttons.append(button)


func _on_option_pressed(index: int) -> void:
	if _answered or challenge == null:
		return
	_answered = true
	selected = index
	var correct: bool = challenge.is_correct(index)
	_clear_option_tweens()
	for i in _buttons.size():
		var button: Button = _buttons[i]
		button.disabled = true
		button.modulate = Color.WHITE
		if i == challenge.correct:
			_paint(button, GOOD_BG, GOOD_EDGE, Color.WHITE)
		elif i == index:
			_paint(button, BAD_BG, BAD_EDGE, Color.WHITE)
		else:
			button.modulate = Color(1, 1, 1, 0.45)

	if challenge.type == Challenge.TYPE_COMPLETE_VERSE:
		%PromptLabel.text = challenge.prompt.replace(Challenge.BLANK, challenge.correct_text().to_upper())

	%StakesBox.visible = false
	%FeedbackBox.visible = true
	%ResultLabel.text = "¡CORRECTO!" if correct else "NO ERA ESA"
	%ResultLabel.add_theme_color_override("font_color", GOOD_TEXT if correct else BAD_TEXT)
	%AnswerLabel.text = "Respuesta correcta: %s" % challenge.correct_text()
	%ExplanationLabel.text = challenge.explanation
	%ReferenceLabel.text = _reference_line(challenge)
	%OutcomeLabel.text = ""
	%ContinueButton.visible = true

	if _feedback_tween != null and _feedback_tween.is_valid():
		_feedback_tween.kill()
	%FeedbackBox.modulate.a = 0.0
	_feedback_tween = create_tween()
	_feedback_tween.tween_property(%FeedbackBox, "modulate:a", 1.0, 0.25)
	answered.emit(index)


## "Referencia: Génesis 7:12", y el texto del versículo solo si hay una versión autorizada.
func _reference_line(item: Challenge) -> String:
	var line: String = "Referencia: %s" % item.reference
	if item.type == Challenge.TYPE_COMPLETE_VERSE and not item.verse_id.is_empty():
		var verse_text: String = VerseProvider.text_of(item.verse_id)
		if not verse_text.is_empty():
			line += "\n%s\n%s" % [verse_text, VerseProvider.attribution()]
	return line


func _paint(button: Button, bg: Color, border: Color, font_color: Color) -> void:
	var look: StyleBoxFlat = UiTheme.box(bg, border, 24, 4, 28.0, 12.0, false)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, look)
	for key in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(key, font_color)


func _on_continue_pressed() -> void:
	if not _answered:
		return
	%ContinueButton.visible = false
	continued.emit()
