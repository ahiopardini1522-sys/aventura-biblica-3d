extends ScreenBase
## Menú principal: título, cinco botones y animación de entrada.
## Cada botón lleva a su pantalla mediante SceneRouter.


func _ready() -> void:
	%PlayButton.pressed.connect(_on_play_pressed)
	%MapsButton.pressed.connect(SceneRouter.go_to.bind("maps"))
	%MultiplayerButton.pressed.connect(SceneRouter.go_to.bind("multiplayer"))
	%CharactersButton.pressed.connect(SceneRouter.go_to.bind("characters"))
	%SettingsButton.pressed.connect(SceneRouter.go_to.bind("settings"))
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	%VersionLabel.text = "v%s  ·  Etapa 1" % version
	UiFx.fade_scale_in([%TitleBlock, %PlayButton, %MapsButton, %MultiplayerButton,
			%CharactersButton, %SettingsButton], 0.08, 0.5)


func _on_play_pressed() -> void:
	GameState.ensure_valid_selection()
	SceneRouter.go_to("board")


## En el menú principal, "atrás" cierra el juego (comportamiento normal de Android).
func _on_back_requested() -> void:
	get_tree().quit()
