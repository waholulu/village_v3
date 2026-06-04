class_name PixelTheme
extends RefCounted

const INK := Color("#f4e7c5")
const MUTED := Color("#b9ad8d")
const WOOD_DARK := Color("#241b18")
const WOOD := Color("#4a3026")
const WOOD_LIGHT := Color("#765039")
const MOSS := Color("#30452d")
const FIRE := Color("#f0a33a")
const DANGER := Color("#d85b4d")

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_shadow_color", "Label", Color(0.05, 0.04, 0.03, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 1)
	theme.set_constant("shadow_offset_y", "Label", 1)
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", FIRE)
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.35))
	theme.set_stylebox("panel", "Panel", _box(WOOD_DARK, WOOD_LIGHT, 2, 8))
	theme.set_stylebox("normal", "Button", _box(WOOD, WOOD_LIGHT, 2, 6))
	theme.set_stylebox("hover", "Button", _box(WOOD_LIGHT, FIRE.darkened(0.25), 2, 6))
	theme.set_stylebox("pressed", "Button", _box(MOSS, FIRE, 2, 6))
	theme.set_stylebox("disabled", "Button", _box(WOOD_DARK.lightened(0.08), WOOD, 2, 6))
	theme.set_stylebox("normal", "ProgressBar", _box(WOOD_DARK, WOOD_LIGHT, 2, 2))
	theme.set_stylebox("fill", "ProgressBar", _box(FIRE.darkened(0.15), FIRE, 1, 1))
	return theme

static func _box(fill: Color, border: Color, width: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin
	box.shadow_color = Color(0.04, 0.025, 0.02, 0.75)
	box.shadow_size = 4
	box.shadow_offset = Vector2(3, 3)
	return box
