# HeatBarOverlay.gd
extends Control

# --- Tunables (can tweak in Inspector) ---
@export var sweet_min: float = 0.25	# 35% (left edge)
@export var sweet_max: float = 0.75	# 65% (right edge)
@export var fill_color: Color = Color(0.3, 1.0, 0.5, 0.18)	# translucent green
@export var edge_color: Color = Color(0.3, 1.0, 0.6, 0.9)	# bright edges
@export var edge_width: float = 2.0
@export var tick_height_pct: float = 0.25	# small top/bottom ticks height (of bar height)

# Optional mid marker
@export var draw_mid_tick: bool = true
@export var mid_tick_width: float = 2.0
@export var mid_tick_color: Color = Color(1, 1, 1, 0.75)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	queue_redraw()
	if not is_connected("resized", Callable(self, "_on_resized")):
		resized.connect(_on_resized)

func _on_resized() -> void:
	queue_redraw()

func set_sweetspot(min_frac: float, max_frac: float) -> void:
	# Call this to tune at runtime
	sweet_min = clamp(min_frac, 0.0, 1.0)
	sweet_max = clamp(max_frac, 0.0, 1.0)
	if sweet_max < sweet_min:
		var t := sweet_min
		sweet_min = sweet_max
		sweet_max = t
	queue_redraw()

func _draw() -> void:
	# guard
	var minf : float = clamp(sweet_min, 0.0, 1.0)
	var maxf : float = clamp(sweet_max, 0.0, 1.0)
	if maxf <= minf:
		return

	# geometry
	var w: float = size.x
	var h: float = size.y
	var x1: float = floor(w * minf)
	var x2: float = ceil(w * maxf)
	var band_w: float = max(1.0, x2 - x1)

	# band fill
	var band := Rect2(Vector2(x1, 0), Vector2(band_w, h))
	draw_rect(band, fill_color, true)

	# vertical edges
	draw_line(Vector2(x1, 0), Vector2(x1, h), edge_color, edge_width)
	draw_line(Vector2(x2, 0), Vector2(x2, h), edge_color, edge_width)

	# small ticks (top & bottom) to pop edges on tiny bars
	var th : float = max(2.0, h * tick_height_pct)
	draw_line(Vector2(x1, 0), Vector2(x1, th), edge_color, edge_width)
	draw_line(Vector2(x1, h - th), Vector2(x1, h), edge_color, edge_width)
	draw_line(Vector2(x2, 0), Vector2(x2, th), edge_color, edge_width)
	draw_line(Vector2(x2, h - th), Vector2(x2, h), edge_color, edge_width)

	# optional mid marker
	if draw_mid_tick:
		var xm: float = floor((x1 + x2) * 0.5)
		draw_line(Vector2(xm, 0), Vector2(xm, h), mid_tick_color, mid_tick_width)
