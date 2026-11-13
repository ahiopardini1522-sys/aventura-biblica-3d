extends ScreenBase
## Menú principal: título, seis botones y animación de entrada.
## EL CAMINO DE LA VIDA es el modo principal; AVENTURA BÍBLICA (escaleras y serpientes) se conserva.
## Cada botón lleva a su pantalla mediante SceneRouter.


func _ready() -> void:
	%LifeButton.pressed.connect(SceneRouter.go_to.bind("life"))
	%PlayButton.pressed.connect(_on_play_pressed)
	%MapsButton.pressed.connect(SceneRouter.go_to.bind("world"))
	%MultiplayerButton.pressed.connect(SceneRouter.go_to.bind("multiplayer"))
	%CharactersButton.pressed.connect(SceneRouter.go_to.bind("characters"))
	%SettingsButton.pressed.connect(SceneRouter.go_to.bind("settings"))
	var version: String = str(ProjectSettings.get_setting("application/config/version", "0.4.0-alfa.1"))
	%VersionLabel.text = "v%s  ·  Camino: etapa 1" % version
	UiFx.fade_scale_in([%TitleBlock, %LifeButton, %PlayButton, %MapsButton, %MultiplayerButton,
			%CharactersButton, %SettingsButton], 0.08, 0.5)
	# Mensaje de arranque: sirve para comprobar el inicio en CI y con "adb logcat".
	print("El Camino de la Vida v%s: menú principal listo" % version)


func _on_play_pressed() -> void:
	GameState.ensure_valid_selection()
	SceneRouter.go_to("board")


## En el menú principal, "atrás" cierra el juego (comportamiento normal de Android).
func _on_back_requested() -> void:
	get_tree().quit()
