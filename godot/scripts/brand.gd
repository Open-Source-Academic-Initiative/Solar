extends RefCounted
## Identidad visual de OpenSAI (Open Source Academic Initiative, opensai.org):
## paleta, tipografía e iconos. Los iconos se rasterizan por código, como el
## resto del proyecto, así que no hay recursos importados.
##
## Colores tomados de la hoja de estilos de opensai.org (2026-09-25). El
## emblema es el «glider» del Juego de la Vida que usa su favicon.

const BLUE := Color("3180c2")         # azul de marca
const BLUE_HEADER := Color("1867a9")  # barra de navegación
const BLUE_DARK := Color("14578e")
const NAVY := Color("0b2d4a")         # degradado de los banners
const ORANGE := Color("ef6c00")       # llamadas a la acción y lema
const RED := Color("ae3436")          # pestaña «Empresas»
const SKY := Color("b8d5ed")          # azul claro para texto secundario
const WHITE := Color("ffffff")

const FONT_NAMES := ["Roboto", "Noto Sans", "DejaVu Sans", "sans-serif"]

# Celdas del glider en una rejilla de 3x3: (columna, fila).
const GLIDER := [Vector2i(1, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)]

const SUPERSAMPLE := 4


static func font(weight: int = 400) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FONT_NAMES)
	f.font_weight = weight
	return f


## Emblema: cuadrado azul redondeado con el glider en blanco.
static func emblem(size: int) -> ImageTexture:
	var s := float(size)
	var shapes: Array = [{"rect": Rect2(0, 0, s, s), "radius": s * 0.18, "color": BLUE}]
	var cell := s * 0.22
	var origin := (s - cell * 3.0) * 0.5
	for c: Vector2i in GLIDER:
		var center := Vector2(origin + (c.x + 0.5) * cell, origin + (c.y + 0.5) * cell)
		shapes.append({"circle": center, "r": cell * 0.36, "color": WHITE})
	return _raster(size, shapes)


## Iconos de los botones del paseo, en blanco sobre transparente.
static func icon(kind: String, size: int, color: Color = WHITE) -> ImageTexture:
	var s := float(size)
	var shapes: Array = []
	match kind:
		"prev", "next":
			# Chevrón «<» con trazo grueso; «>» es su espejo.
			var pts := PackedVector2Array([
				Vector2(0.58, 0.10), Vector2(0.72, 0.22), Vector2(0.44, 0.50),
				Vector2(0.72, 0.78), Vector2(0.58, 0.90), Vector2(0.28, 0.50)])
			if kind == "next":
				for i in pts.size():
					pts[i].x = 1.0 - pts[i].x
			shapes.append({"poly": _scaled(pts, s), "color": color})
		"home":
			shapes.append({"poly": _scaled(PackedVector2Array([
				Vector2(0.5, 0.1), Vector2(0.94, 0.5), Vector2(0.06, 0.5)]), s), "color": color})
			shapes.append({"rect": Rect2(s * 0.18, s * 0.46, s * 0.64, s * 0.42), "radius": 0.0, "color": color})
			shapes.append({"rect": Rect2(s * 0.42, s * 0.62, s * 0.16, s * 0.26), "radius": 0.0, "color": Color(0, 0, 0, 0)})
		"pause":
			shapes.append({"rect": Rect2(s * 0.2, s * 0.14, s * 0.2, s * 0.72), "radius": s * 0.04, "color": color})
			shapes.append({"rect": Rect2(s * 0.6, s * 0.14, s * 0.2, s * 0.72), "radius": s * 0.04, "color": color})
		"close":
			shapes.append({"poly": _scaled(PackedVector2Array([
				Vector2(0.14, 0.26), Vector2(0.26, 0.14), Vector2(0.86, 0.74), Vector2(0.74, 0.86)]), s), "color": color})
			shapes.append({"poly": _scaled(PackedVector2Array([
				Vector2(0.74, 0.14), Vector2(0.86, 0.26), Vector2(0.26, 0.86), Vector2(0.14, 0.74)]), s), "color": color})
		"play":
			shapes.append({"poly": _scaled(PackedVector2Array([
				Vector2(0.24, 0.12), Vector2(0.86, 0.5), Vector2(0.24, 0.88)]), s), "color": color})
	return _raster(size, shapes)


static func _scaled(pts: PackedVector2Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p * s)
	return out


## Rasteriza figuras con supermuestreo. La última figura que contiene la
## muestra gana, así que un color transparente recorta (la puerta de la casa).
static func _raster(size: int, shapes: Array) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var n := SUPERSAMPLE
	var weight := 1.0 / float(n * n)
	for y in size:
		for x in size:
			var acc := Color(0, 0, 0, 0)
			for sy in n:
				for sx in n:
					var p := Vector2(x + (sx + 0.5) / n, y + (sy + 0.5) / n)
					var hit := Color(0, 0, 0, 0)
					for shape: Dictionary in shapes:
						if _contains(shape, p):
							hit = shape["color"]
					acc += Color(hit.r * hit.a, hit.g * hit.a, hit.b * hit.a, hit.a) * weight
			if acc.a > 0.0:
				img.set_pixel(x, y, Color(acc.r / acc.a, acc.g / acc.a, acc.b / acc.a, acc.a))
	return ImageTexture.create_from_image(img)


static func _contains(shape: Dictionary, p: Vector2) -> bool:
	if shape.has("circle"):
		return p.distance_to(shape["circle"]) <= float(shape["r"])
	if shape.has("poly"):
		return Geometry2D.is_point_in_polygon(p, shape["poly"])
	var rect: Rect2 = shape["rect"]
	if not rect.has_point(p):
		return false
	var r: float = shape["radius"]
	if r <= 0.0:
		return true
	var inner := rect.grow(-r)
	var nearest := Vector2(clampf(p.x, inner.position.x, inner.end.x), clampf(p.y, inner.position.y, inner.end.y))
	return p.distance_to(nearest) <= r
