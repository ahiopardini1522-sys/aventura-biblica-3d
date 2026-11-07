class_name ScreenHeader
extends HBoxContainer
## Cabecera común de las pantallas secundarias: botón VOLVER + título.

signal back_pressed

@export var title: String = "":
	set(value):
		title = value
		if is_node_ready():
			%TitleLabel.text = value


func _ready() -> void:
	%TitleLabel.text = title
	%BackButton.pressed.connect(_on_back_pressed)


func _on_back_pressed() -> void:
	back_pressed.emit()
	SceneRouter.go_back()
