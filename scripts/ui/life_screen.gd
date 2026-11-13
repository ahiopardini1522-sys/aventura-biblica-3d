extends ScreenBase
## EL CAMINO DE LA VIDA (etapa 1, base): pantalla de entrada del modo nuevo.
## Todavía no hay partida: muestra qué será el modo y en qué etapa va su desarrollo.
## El juego de escaleras y serpientes (AVENTURA BÍBLICA) sigue disponible en el menú principal.

## Etapa en la que está el desarrollo (1 = base). Las anteriores se muestran como hechas.
const CURRENT_STAGE := 1
## Plan del modo, en orden. "title" es lo que ve el jugador; "text", qué incluye.
const STAGES: Array = [
	{"title": "Base", "text": "El modo nuevo en el menú, sin tocar lo que ya funciona."},
	{"title": "Camino y ruleta", "text": "Tablero con bifurcaciones, ruleta 3D y un auto que avanza."},
	{"title": "Vida y monedas", "text": "Eventos, decisiones que cambian el camino y puntaje final."},
	{"title": "Desafíos bíblicos", "text": "Las preguntas del juego, con premio en monedas."},
	{"title": "Contra la computadora", "text": "De 1 a 3 rivales automáticos."},
	{"title": "Personalización", "text": "Personajes y vehículos para elegir y comprar."},
	{"title": "Escenarios", "text": "Ciudades, iglesias y montañas a lo largo del camino."},
	{"title": "En línea", "text": "Salas y turnos sincronizados con otros jugadores."},
	{"title": "Cierre", "text": "Música, pruebas en el teléfono y versión final."},
]


func _ready() -> void:
	for index in STAGES.size():
		%StageList.add_child(_build_stage_row(index))
	%StartButton.disabled = true
	%StartButton.text = "EMPEZAR VIAJE (ETAPA 2)"
	%ClassicButton.pressed.connect(_on_classic_pressed)
	UiFx.fade_scale_in([%InfoPanel, %StagePanel], 0.1, 0.45)


## Una fila de la lista: número, nombre de la etapa y su estado.
func _build_stage_row(index: int) -> Control:
	var stage: Dictionary = STAGES[index]
	var number: int = index + 1
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var title := Label.new()
	var mark: String = "PRÓXIMA"
	if number < CURRENT_STAGE:
		mark = "HECHA"
	elif number == CURRENT_STAGE:
		mark = "EN CURSO"
	title.text = "%d. %s  ·  %s" % [number, str(stage["title"]), mark]
	title.add_theme_font_size_override("font_size", 30)
	if number <= CURRENT_STAGE:
		title.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT)
	row.add_child(title)
	var text := Label.new()
	text.theme_type_variation = &"DimLabel"
	text.text = str(stage["text"])
	text.add_theme_font_size_override("font_size", 24)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(text)
	return row


## Mientras el Camino no sea jugable, este botón abre el juego de escaleras y serpientes.
func _on_classic_pressed() -> void:
	GameState.ensure_valid_selection()
	SceneRouter.go_to("board")
