class_name CharacterPreview
extends SubViewportContainer
## Vista previa 3D de un personaje: una ficha que gira despacio dentro de su propio mundo 3D.
## Se puede reutilizar en cualquier pantalla (personajes, selección de partida, etc.).

const SPIN_SPEED := 0.9 # radianes por segundo

@onready var _pivot: Node3D = %Pivot
@onready var _token: PlayerToken = %Token
@onready var _camera: Camera3D = %PreviewCamera
@onready var _light: DirectionalLight3D = %PreviewLight


func _ready() -> void:
	_camera.look_at_from_position(Vector3(0.0, 1.0, 3.3), Vector3(0.0, 0.62, 0.0))
	_light.look_at_from_position(Vector3(2.0, 3.0, 2.5), Vector3.ZERO)


func _process(delta: float) -> void:
	_pivot.rotation.y = wrapf(_pivot.rotation.y + SPIN_SPEED * delta, 0.0, TAU)


## Muestra al personaje indicado (entrada de CharacterCatalog).
func show_character(character: Dictionary) -> void:
	_token.setup(character)
