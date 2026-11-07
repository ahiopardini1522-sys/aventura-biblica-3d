class_name UiTheme
extends RefCounted
## Tema visual compartido: vidrio oscuro + dorado, pensado para pantallas táctiles.
## Se aplica una sola vez a la ventana raíz desde SceneRouter.

const GOLD := Color(0.96, 0.77, 0.33)
const GOLD_LIGHT := Color(1.0, 0.88, 0.54)
const GOLD_DARK := Color(0.69, 0.48, 0.11)
const NAVY := Color(0.05, 0.08, 0.17)
const GLASS := Color(0.05, 0.08, 0.17, 0.78)
const TEXT := Color(0.96, 0.95, 0.91)
const TEXT_DIM := Color(0.73, 0.76, 0.84)
const OK_GREEN := Color(0.44, 0.81, 0.50)
const WARN_RED := Color(0.88, 0.40, 0.36)
const INK := Color(0.13, 0.07, 0.01)

static var _theme: Theme


static func build() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 34
	_style_buttons(t)
	_style_labels(t)
	_style_panels(t)
	_style_sliders(t)
	t.set_constant("separation", "VBoxContainer", 16)
	t.set_constant("separation", "HBoxContainer", 16)
	_theme = t
	return t


static func box(bg: Color, border: Color, radius: int = 24, border_w: int = 2,
		margin_h: float = 32.0, margin_v: float = 14.0, shadow: bool = true) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin_h
	sb.content_margin_right = margin_h
	sb.content_margin_top = margin_v
	sb.content_margin_bottom = margin_v
	if shadow:
		sb.shadow_color = Color(0, 0, 0, 0.38)
		sb.shadow_size = 12
		sb.shadow_offset = Vector2(0, 5)
	return sb


static func _style_buttons(t: Theme) -> void:
	# Botón normal (vidrio oscuro). "pressed" también es el aspecto de "seleccionado".
	t.set_stylebox("normal", "Button", box(Color(0.07, 0.11, 0.22, 0.74), Color(1, 1, 1, 0.22)))
	t.set_stylebox("hover", "Button", box(Color(0.12, 0.18, 0.34, 0.86), Color(GOLD, 0.7)))
	t.set_stylebox("pressed", "Button", box(Color(0.16, 0.22, 0.40, 0.95), GOLD, 24, 3))
	t.set_stylebox("hover_pressed", "Button", box(Color(0.18, 0.25, 0.44, 0.97), GOLD_LIGHT, 24, 3))
	t.set_stylebox("disabled", "Button", box(Color(0.10, 0.12, 0.18, 0.55), Color(1, 1, 1, 0.10), 24, 2, 32.0, 14.0, false))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GOLD_LIGHT)
	t.set_color("font_hover_pressed_color", "Button", GOLD_LIGHT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.42))
	t.set_font_size("font_size", "Button", 36)

	# Botón principal (dorado).
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", box(GOLD, GOLD_DARK, 26, 3, 36.0, 16.0))
	t.set_stylebox("hover", "PrimaryButton", box(GOLD_LIGHT, GOLD_DARK, 26, 3, 36.0, 16.0))
	t.set_stylebox("pressed", "PrimaryButton", box(GOLD_DARK, INK, 26, 3, 36.0, 16.0))
	t.set_stylebox("hover_pressed", "PrimaryButton", box(GOLD_DARK, INK, 26, 3, 36.0, 16.0))
	t.set_stylebox("disabled", "PrimaryButton", box(Color(0.45, 0.42, 0.33, 0.7), Color(1, 1, 1, 0.12), 26, 2, 36.0, 16.0, false))
	t.set_color("font_color", "PrimaryButton", INK)
	t.set_color("font_hover_color", "PrimaryButton", INK)
	t.set_color("font_pressed_color", "PrimaryButton", GOLD_LIGHT)
	t.set_color("font_hover_pressed_color", "PrimaryButton", GOLD_LIGHT)
	t.set_color("font_disabled_color", "PrimaryButton", Color(1, 1, 1, 0.55))
	t.set_font_size("font_size", "PrimaryButton", 44)


static func _style_labels(t: Theme) -> void:
	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 34)

	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", 92)
	t.set_color("font_color", "TitleLabel", GOLD_LIGHT)
	t.set_color("font_outline_color", "TitleLabel", Color(0.28, 0.14, 0.03))
	t.set_constant("outline_size", "TitleLabel", 16)
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 6)

	t.set_type_variation("SubtitleLabel", "Label")
	t.set_font_size("font_size", "SubtitleLabel", 36)
	t.set_color("font_color", "SubtitleLabel", TEXT)
	t.set_color("font_shadow_color", "SubtitleLabel", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "SubtitleLabel", 0)
	t.set_constant("shadow_offset_y", "SubtitleLabel", 3)

	t.set_type_variation("HeadingLabel", "Label")
	t.set_font_size("font_size", "HeadingLabel", 56)
	t.set_color("font_color", "HeadingLabel", GOLD_LIGHT)
	t.set_color("font_outline_color", "HeadingLabel", Color(0.20, 0.10, 0.02, 0.9))
	t.set_constant("outline_size", "HeadingLabel", 8)

	t.set_type_variation("DimLabel", "Label")
	t.set_font_size("font_size", "DimLabel", 30)
	t.set_color("font_color", "DimLabel", TEXT_DIM)

	t.set_type_variation("ValueLabel", "Label")
	t.set_font_size("font_size", "ValueLabel", 44)
	t.set_color("font_color", "ValueLabel", GOLD)


static func _style_panels(t: Theme) -> void:
	var glass: StyleBoxFlat = box(GLASS, Color(1, 1, 1, 0.14), 30, 2, 36.0, 30.0)
	t.set_stylebox("panel", "PanelContainer", glass)
	t.set_stylebox("panel", "Panel", box(GLASS, Color(1, 1, 1, 0.14), 30, 2, 0.0, 0.0))


static func _style_sliders(t: Theme) -> void:
	var track: StyleBoxFlat = box(Color(1, 1, 1, 0.18), Color(0, 0, 0, 0), 8, 0, 0.0, 7.0, false)
	var fill: StyleBoxFlat = box(GOLD, Color(0, 0, 0, 0), 8, 0, 0.0, 7.0, false)
	var fill_hi: StyleBoxFlat = box(GOLD_LIGHT, Color(0, 0, 0, 0), 8, 0, 0.0, 7.0, false)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	var knob: Texture2D = _knob_texture(GOLD, 60)
	var knob_hi: Texture2D = _knob_texture(GOLD_LIGHT, 60)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob_hi)
	t.set_icon("grabber_disabled", "HSlider", _knob_texture(Color(0.5, 0.5, 0.5), 60))


## Punto de color con borde suave, útil como icono de botones de lista.
static func dot_icon(color: Color, pixels: int = 48) -> Texture2D:
	return _knob_texture(color, pixels)


## Círculo dorado con borde suave, usado como agarre de los deslizadores.
static func _knob_texture(color: Color, pixels: int) -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.78, 0.86, 1.0])
	gradient.colors = PackedColorArray([color, color, Color(color, 0.0), Color(color, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = pixels
	tex.height = pixels
	return tex
