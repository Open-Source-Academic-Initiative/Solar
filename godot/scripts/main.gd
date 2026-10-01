extends Node3D
## Paseo interactivo por el sistema solar cartoon.
##
## Clic en un cuerpo: la cámara vuela hasta él, lo acompaña en su órbita y
## muestra su ficha. Flechas izquierda/derecha o los botones recorren el paseo
## en orden; Esc vuelve a la vista general. Arrastrar gira la cámara y la rueda
## acerca o aleja. Todo se construye por código a partir de solar_data.gd.

const Data := preload("res://scripts/solar_data.gd")
const Brand := preload("res://scripts/brand.gd")
const ToonShader := preload("res://shaders/toon_planet.gdshader")
const OutlineShader := preload("res://shaders/outline.gdshader")
const SunShader := preload("res://shaders/sun.gdshader")
const CoronaShader := preload("res://shaders/sun_corona.gdshader")
const OrbitShader := preload("res://shaders/orbit_dashed.gdshader")
const RingsShader := preload("res://shaders/saturn_rings.gdshader")
const SkyShader := preload("res://shaders/starry_sky.gdshader")

const FLIGHT_SECONDS := 1.6
const FOCUS_TIME_SCALE := 0.25
# Encuadre de la cámara de Blender: 42 u, 32° de elevación, balanceo de ±12°.
const OVERVIEW_TARGET := Vector3(0.0, -1.0, 2.5)
const OVERVIEW_DISTANCE := 42.0
const OVERVIEW_PITCH := 0.5585
const OVERVIEW_SWAY := 0.2094
const FOCUS_PITCH := 0.3
const FOCUS_YAW := 2.2  # desde la cara lejana del Sol: se ve sobre todo el lado de día
const SUN_FOCUS_YAW := 0.35
const PANEL_SHIFT := 0.24  # desplaza el cuerpo a la izquierda, lejos de la ficha

# Paleta de OpenSAI (ver brand.gd).
const INK := Brand.NAVY
const PANEL_BG := Color(0.043, 0.176, 0.29, 0.92)
const TEXT := Brand.WHITE
const MUTED := Brand.SKY
const ACCENT := Brand.ORANGE
const ATTRIBUTION := "© 2026 OpenSAI · opensai.org\nCódigo bajo licencia MIT\nHecho con Godot Engine (MIT)"

var sim_time := 0.0
var base_speed := 1.0
var current_speed := 1.0
var paused := false
var bodies := {}
var focus_id := ""
var camera: Camera3D
var belt: MultiMeshInstance3D

var user_yaw := 0.0
var user_pitch := 0.0
var user_zoom := 1.0
var flight_t := 1.0
var flight_from_pos := Vector3.ZERO
var flight_from_look := Vector3.ZERO
var current_look := Vector3.ZERO
var dragging := false
var drag_moved := 0.0

var welcome_panel: PanelContainer
var info_panel: PanelContainer
var info_style: StyleBoxFlat
var info_index: Label
var info_title: Label
var info_kind: Label
var info_text: Label
var info_facts: GridContainer
var pause_button: Button
var close_button: Button
var icons := {}
var speed_label: Label


func _ready() -> void:
	_build_environment()
	_build_sun()
	for id: String in Data.BODIES:
		_build_body(id)
	_build_orbits()
	_build_belt()
	_build_camera()
	_build_ui()
	_update_bodies()
	_update_camera(0.0)
	_refresh_ui()


func _process(delta: float) -> void:
	var target_speed := 0.0
	if not paused:
		target_speed = base_speed * (1.0 if focus_id == "" else FOCUS_TIME_SCALE)
	current_speed = lerpf(current_speed, target_speed, 1.0 - exp(-4.0 * delta))
	sim_time += delta * current_speed
	_update_bodies()
	_update_camera(delta)
	speed_label.text = "Tiempo x%.2f" % current_speed


# --- API del paseo (también la usa tests/tour_test.gd) -------------------------


func focus_body(id: String) -> void:
	if id == focus_id:
		return
	flight_from_pos = camera.global_position
	flight_from_look = current_look
	flight_t = 0.0
	focus_id = id
	user_yaw = 0.0
	user_pitch = 0.0
	user_zoom = 1.0
	_refresh_ui()


func show_overview() -> void:
	focus_body("")


func tour_step(step: int) -> void:
	var order: Array = Data.TOUR
	var i := order.find(focus_id)
	if i == -1:
		i = 0 if step > 0 else order.size() - 1
	else:
		i = wrapi(i + step, 0, order.size())
	focus_body(order[i])


func set_paused(value: bool) -> void:
	paused = value
	pause_button.text = "Reanudar" if paused else "Pausa"
	pause_button.icon = icons["play"] if paused else icons["pause"]


func quit_app() -> void:
	get_tree().quit()


func pick_at(screen_pos: Vector2) -> String:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 600.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider: Object = hit["collider"]
	return String(collider.get_meta("body_id", ""))


func body_position(id: String) -> Vector3:
	return (bodies[id]["holder"] as Node3D).global_position


# --- entrada -------------------------------------------------------------------


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				dragging = true
				drag_moved = 0.0
			else:
				dragging = false
				if drag_moved < 6.0:
					var id := pick_at(mb.position)
					if id != "":
						focus_body(id)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			user_zoom = maxf(0.35, user_zoom * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			user_zoom = minf(2.5, user_zoom * 1.1)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging:
			drag_moved += mm.relative.length()
			user_yaw -= mm.relative.x * 0.006
			user_pitch += mm.relative.y * 0.004
		else:
			var over := pick_at(mm.position) != ""
			Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.keycode:
			KEY_RIGHT:
				tour_step(1)
			KEY_LEFT:
				tour_step(-1)
			KEY_ESCAPE:
				show_overview()
			KEY_SPACE:
				set_paused(not paused)


# --- animación -----------------------------------------------------------------


func _update_bodies() -> void:
	var loop := Data.LOOP_SECONDS
	for id: String in bodies:
		if id == "sol":
			continue
		var b: Dictionary = bodies[id]
		var center := Vector3.ZERO
		var parent: String = b["parent"]
		if parent != "":
			center = (bodies[parent]["holder"] as Node3D).position
		var start: float = b["start"]
		var orbits: float = b["orbits"]
		var spins: float = b["spins"]
		var dist: float = b["distance"]
		var ang := start + TAU * orbits * sim_time / loop
		(b["holder"] as Node3D).position = center + Vector3(cos(ang) * dist, 0.0, -sin(ang) * dist)
		(b["body"] as Node3D).rotation.y = TAU * spins * sim_time / loop
	belt.rotation.y = TAU * sim_time / loop


func _desired_view() -> Array:
	var target := OVERVIEW_TARGET
	var base_dir := Vector3(0.0, 0.0, 1.0)
	var yaw := user_yaw
	var pitch := OVERVIEW_PITCH + user_pitch
	var dist := OVERVIEW_DISTANCE * user_zoom
	var shift := 0.0
	if focus_id == "":
		yaw -= OVERVIEW_SWAY * cos(TAU * sim_time / Data.LOOP_SECONDS)
	else:
		var b: Dictionary = bodies[focus_id]
		target = body_position(focus_id)
		var flat := Vector3(target.x, 0.0, target.z)
		if flat.length() > 0.01:
			base_dir = flat.normalized()
			yaw += FOCUS_YAW
		else:
			yaw += SUN_FOCUS_YAW
		pitch = FOCUS_PITCH + user_pitch
		var focus_distance: float = b["focus"]
		dist = focus_distance * user_zoom
		shift = PANEL_SHIFT
	pitch = clampf(pitch, 0.05, 1.35)
	var h := base_dir.rotated(Vector3.UP, yaw)
	var pos := target + (h * cos(pitch) + Vector3.UP * sin(pitch)) * dist
	var look := target
	if shift > 0.0:
		var right := (target - pos).normalized().cross(Vector3.UP).normalized()
		look += right * dist * shift
	return [pos, look]


func _update_camera(delta: float) -> void:
	var view := _desired_view()
	var pos: Vector3 = view[0]
	var look: Vector3 = view[1]
	if flight_t < 1.0:
		flight_t = minf(1.0, flight_t + delta / FLIGHT_SECONDS)
		var e := smoothstep(0.0, 1.0, flight_t)
		var lift := sin(PI * e) * flight_from_pos.distance_to(pos) * 0.18
		pos = flight_from_pos.lerp(pos, e) + Vector3.UP * lift
		look = flight_from_look.lerp(look, e)
	current_look = look
	camera.look_at_from_position(pos, look, Vector3.UP)


# --- construcción de la escena ------------------------------------------------


func _build_environment() -> void:
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SkyShader
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 0.95
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 37.5  # 30 mm sobre sensor de 36 mm en 16:9, como en Blender
	camera.near = 0.05
	camera.far = 600.0
	add_child(camera)
	camera.make_current()


func _build_sun() -> void:
	var r := Data.SUN_RADIUS
	var holder := Node3D.new()
	holder.name = "Sol"
	add_child(holder)

	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = 2.0 * r
	mesh.radial_segments = 96
	mesh.rings = 48
	var sun_material := ShaderMaterial.new()
	sun_material.shader = SunShader
	sun_material.next_pass = _outline(0.07)
	var sun := MeshInstance3D.new()
	sun.mesh = mesh
	sun.material_override = sun_material
	holder.add_child(sun)

	var half := r * 2.6
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0 * half, 2.0 * half)
	var corona_material := ShaderMaterial.new()
	corona_material.shader = CoronaShader
	corona_material.set_shader_parameter("sun_radius", r)
	corona_material.set_shader_parameter("half_size", half)
	corona_material.set_shader_parameter("period", Data.LOOP_SECONDS)
	var corona := MeshInstance3D.new()
	corona.name = "Corona"
	corona.mesh = quad
	corona.material_override = corona_material
	corona.extra_cull_margin = 2.0 * half  # el quad se orienta a la cámara en el shader
	holder.add_child(corona)

	_add_pick(holder, "sol", r)
	_add_label(holder, "Sol", r * 1.75)
	bodies["sol"] = {"holder": holder, "body": sun, "radius": r, "distance": 0.0,
		"orbits": 0.0, "start": 0.0, "spins": 0.0, "parent": "", "focus": 9.5}


func _build_body(id: String) -> void:
	var d: Dictionary = Data.BODIES[id]
	var r: float = d["radius"]
	var holder := Node3D.new()
	holder.name = String(d["name"])
	add_child(holder)
	var tilt := Node3D.new()
	tilt.rotation.x = deg_to_rad(float(d["tilt"]))
	holder.add_child(tilt)

	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = 2.0 * r
	mesh.radial_segments = 64
	mesh.rings = 32
	var material := _toon_material(d["look"], r)
	material.next_pass = _outline(maxf(0.035, r * 0.07))
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	tilt.add_child(body)

	var focus := r * 4.2 + 1.2
	if d.get("rings", false):
		tilt.add_child(_saturn_rings(r))
		focus = r * 5.5 + 1.5
	_add_pick(holder, id, maxf(r * 1.3, 0.45))
	_add_label(holder, String(d["name"]), r + 0.45)
	bodies[id] = {"holder": holder, "body": body, "radius": r,
		"distance": float(d["distance"]), "orbits": float(d["orbits"]),
		"start": deg_to_rad(float(d["start"])), "spins": float(d["spins"]),
		"parent": String(d["parent"]), "focus": focus}


func _build_orbits() -> void:
	for id: String in Data.BODIES:
		var d: Dictionary = Data.BODIES[id]
		if String(d["parent"]) != "":
			continue
		var dist: float = d["distance"]
		var torus := TorusMesh.new()
		torus.inner_radius = dist - 0.022
		torus.outer_radius = dist + 0.022
		torus.rings = 256
		torus.ring_segments = 6
		var material := ShaderMaterial.new()
		material.shader = OrbitShader
		material.set_shader_parameter("dashes", roundf(dist * 7.0))
		var orbit := MeshInstance3D.new()
		orbit.name = "Trayectoria_" + String(d["name"])
		orbit.mesh = torus
		orbit.material_override = material
		add_child(orbit)


func _build_belt() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rock := SphereMesh.new()
	rock.radius = 1.0
	rock.height = 2.0
	rock.radial_segments = 6
	rock.rings = 3
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = rock
	multimesh.instance_count = 240
	for i in multimesh.instance_count:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(Data.BELT.x, Data.BELT.y)
		var size := rng.randf_range(0.05, 0.14)
		var rotation_basis := Basis.from_euler(Vector3(rng.randf() * 6.0, rng.randf() * 6.0, rng.randf() * 6.0))
		var scale_basis := Basis.from_scale(Vector3(size * rng.randf_range(0.7, 1.4), size * rng.randf_range(0.6, 1.0), size))
		var origin := Vector3(cos(a) * r, rng.randf_range(-0.18, 0.18), -sin(a) * r)
		multimesh.set_instance_transform(i, Transform3D(rotation_basis * scale_basis, origin))
	var material := _toon_material({"mode": 2, "flat": "a08a78"}, 1.0)
	material.next_pass = _outline(0.22)
	belt = MultiMeshInstance3D.new()
	belt.name = "Cinturon_Asteroides"
	belt.multimesh = multimesh
	belt.material_override = material
	add_child(belt)


func _saturn_rings(r: float) -> MeshInstance3D:
	var inner := r * 1.35
	var outer := r * 2.3
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0 * outer, 2.0 * outer)
	var material := ShaderMaterial.new()
	material.shader = RingsShader
	material.set_shader_parameter("inner", inner)
	material.set_shader_parameter("outer", outer)
	material.set_shader_parameter("palette", _palette([[0.0, "b89a6a"], [0.12, "e7cf9c"],
		[0.38, "f4e3b8"], [0.58, "1a1030"], [0.63, "d8bb85"], [0.84, "c6a676"], [0.95, "e9d3a6"]]))
	var rings := MeshInstance3D.new()
	rings.name = "Anillos"
	rings.mesh = plane
	rings.material_override = material
	return rings


func _toon_material(look: Dictionary, r: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ToonShader
	m.set_shader_parameter("radius", r)
	m.set_shader_parameter("pattern", int(look.get("mode", 2)))
	m.set_shader_parameter("noise_scale", float(look.get("scale", 2.0)))
	m.set_shader_parameter("wobble", float(look.get("wobble", 0.2)))
	if look.has("palette"):
		m.set_shader_parameter("palette", _palette(look["palette"]))
	if look.has("flat"):
		m.set_shader_parameter("flat_color", Color(String(look["flat"])))
	if look.has("caps"):
		var caps: Array = look["caps"]
		m.set_shader_parameter("caps_level", float(caps[0]))
		m.set_shader_parameter("caps_color", Color(String(caps[1])))
	if look.has("craters"):
		var craters: Array = look["craters"]
		m.set_shader_parameter("crater_scale", float(craters[0]))
		m.set_shader_parameter("crater_size", float(craters[1]))
		m.set_shader_parameter("crater_color", Color(String(craters[2])))
	if look.has("spot"):
		var spot: Array = look["spot"]
		m.set_shader_parameter("spot_center", spot[0])
		m.set_shader_parameter("spot_radius", float(spot[1]))
		m.set_shader_parameter("spot_color", Color(String(spot[2])))
		if String(spot[3]) != "":
			m.set_shader_parameter("spot_ring", 1.3)
			m.set_shader_parameter("spot_ring_color", Color(String(spot[3])))
	return m


func _palette(stops: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for stop: Array in stops:
		offsets.append(float(stop[0]))
		colors.append(Color(String(stop[1])))
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 512
	return texture


func _outline(thickness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = OutlineShader
	m.set_shader_parameter("thickness", thickness)
	return m


func _add_pick(holder: Node3D, id: String, r: float) -> void:
	var shape := SphereShape3D.new()
	shape.radius = r
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.set_meta("body_id", id)
	body.add_child(collision)
	holder.add_child(body)


func _add_label(holder: Node3D, text: String, height: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 32
	label.outline_size = 10
	label.pixel_size = 0.0007
	label.fixed_size = true
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(1.0, 1.0, 1.0, 0.92)
	label.outline_modulate = Color(INK, 0.9)
	label.font = Brand.font(500)
	label.position = Vector3(0.0, height, 0.0)
	holder.add_child(label)


# --- interfaz -----------------------------------------------------------------


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.name = "UI"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = Brand.font()
	root.theme = theme
	layer.add_child(root)
	for kind: String in ["prev", "next", "home", "pause", "play", "close"]:
		icons[kind] = Brand.icon(kind, 36)

	_build_header(root)

	welcome_panel = PanelContainer.new()
	welcome_panel.add_theme_stylebox_override("panel", _panel_style(Brand.BLUE))
	welcome_panel.position = Vector2(28, 96)
	welcome_panel.custom_minimum_size = Vector2(390, 0)
	root.add_child(welcome_panel)
	var welcome := VBoxContainer.new()
	welcome.add_theme_constant_override("separation", 8)
	welcome_panel.add_child(welcome)
	welcome.add_child(_label("¡Bienvenido a bordo!", 20, TEXT))
	var intro := _label("Haz clic en cualquier planeta para visitarlo, o pulsa Siguiente para empezar el paseo desde el Sol.", 16, TEXT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	welcome.add_child(intro)
	var controls := _label("Arrastrar: girar · Rueda: acercar · Flechas: paseo · Esc: vista general · Espacio: pausa", 13, MUTED)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	welcome.add_child(controls)

	info_panel = PanelContainer.new()
	info_style = _panel_style(ACCENT)
	info_panel.add_theme_stylebox_override("panel", info_style)
	info_panel.anchor_left = 1.0
	info_panel.anchor_right = 1.0
	info_panel.anchor_top = 0.0
	info_panel.anchor_bottom = 1.0
	info_panel.offset_left = -470.0
	info_panel.offset_right = -28.0
	info_panel.offset_top = 92.0
	info_panel.offset_bottom = -112.0
	root.add_child(info_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	info_panel.add_child(column)
	info_index = _label("", 14, MUTED)
	column.add_child(info_index)
	info_title = _label("", 44, ACCENT)
	info_title.add_theme_font_override("font", Brand.font(500))
	column.add_child(info_title)
	info_kind = _label("", 17, MUTED)
	info_kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(info_kind)
	info_text = _label("", 18, TEXT)
	info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(info_text)
	column.add_child(HSeparator.new())
	info_facts = GridContainer.new()
	info_facts.columns = 2
	info_facts.add_theme_constant_override("h_separation", 14)
	info_facts.add_theme_constant_override("v_separation", 8)
	column.add_child(info_facts)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var hint := _label("Haz clic en otro cuerpo o usa las flechas para seguir el paseo.", 13, MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)

	var bar_panel := PanelContainer.new()
	bar_panel.add_theme_stylebox_override("panel", _panel_style(Brand.BLUE))
	bar_panel.anchor_left = 0.5
	bar_panel.anchor_right = 0.5
	bar_panel.anchor_top = 1.0
	bar_panel.anchor_bottom = 1.0
	bar_panel.offset_left = -440.0
	bar_panel.offset_right = 440.0
	bar_panel.offset_top = -92.0
	bar_panel.offset_bottom = -24.0
	bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bar_panel)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 10)
	bar_panel.add_child(bar)
	bar.add_child(_button("Anterior", tour_step.bind(-1), icons["prev"]))
	bar.add_child(_button("Vista general", show_overview, icons["home"]))
	var next := _button("Siguiente", tour_step.bind(1), icons["next"])
	next.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	next.add_theme_stylebox_override("normal", _button_style(Brand.ORANGE))
	next.add_theme_stylebox_override("hover", _button_style(Brand.ORANGE.lightened(0.15)))
	next.add_theme_stylebox_override("pressed", _button_style(Brand.ORANGE.darkened(0.2)))
	bar.add_child(next)
	pause_button = _button("Pausa", func() -> void: set_paused(not paused), icons["pause"])
	bar.add_child(pause_button)
	speed_label = _label("Tiempo x1.00", 15, MUTED)
	speed_label.custom_minimum_size = Vector2(110, 0)
	speed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(speed_label)
	var slider := HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 3.0
	slider.step = 0.1
	slider.value = 1.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size = Vector2(150, 24)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void: base_speed = v)
	bar.add_child(slider)

	var legend := _label(ATTRIBUTION, 12, MUTED)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.anchor_top = 1.0
	legend.anchor_bottom = 1.0
	legend.offset_left = 28.0
	legend.offset_right = 360.0
	legend.offset_top = -86.0
	legend.offset_bottom = -24.0
	legend.grow_vertical = Control.GROW_DIRECTION_BEGIN
	legend.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	legend.add_theme_color_override("font_outline_color", INK)
	legend.add_theme_constant_override("outline_size", 3)
	root.add_child(legend)


## Barra superior al estilo de la navegación de opensai.org: emblema, marca y
## nombre del proyecto entre llaves, como en los títulos del sitio.
func _build_header(root: Control) -> void:
	var header := PanelContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Brand.BLUE_HEADER, 0.9)
	style.border_color = Brand.ORANGE
	style.border_width_bottom = 3
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	header.add_theme_stylebox_override("panel", style)
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	root.add_child(header)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	header.add_child(row)

	var emblem := TextureRect.new()
	emblem.texture = Brand.emblem(96)
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.custom_minimum_size = Vector2(44, 44)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(emblem)
	var brand := _label("OpenSAI", 30, TEXT)
	brand.add_theme_font_override("font", Brand.font(500))
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(brand)
	var title := _label("{ Sistema Solar Cartoon }", 22, TEXT)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var subtitle := _label("Paseo interactivo · tamaños y distancias no están a escala", 15, MUTED)
	subtitle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(subtitle)
	close_button = _button("Cerrar", quit_app, icons["close"])
	close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_button.tooltip_text = "Salir del paseo"
	close_button.add_theme_stylebox_override("normal", _button_style(Brand.RED))
	close_button.add_theme_stylebox_override("hover", _button_style(Brand.RED.lightened(0.15)))
	close_button.add_theme_stylebox_override("pressed", _button_style(Brand.RED.darkened(0.2)))
	close_button.visible = not OS.has_feature("web")  # en el navegador quit() solo congela el lienzo
	row.add_child(close_button)


func _refresh_ui() -> void:
	var overview := focus_id == ""
	welcome_panel.visible = overview
	info_panel.visible = not overview
	if overview:
		return
	var info: Dictionary = Data.INFO[focus_id]
	var display_name := "Sol"
	var accent := ACCENT
	if focus_id != "sol":
		var d: Dictionary = Data.BODIES[focus_id]
		display_name = String(d["name"])
		accent = Color(String(d["accent"]))
	info_index.text = "Parada %d de %d" % [Data.TOUR.find(focus_id) + 1, Data.TOUR.size()]
	info_title.text = display_name
	info_title.add_theme_color_override("font_color", accent)
	info_style.border_color = accent
	info_kind.text = String(info["kind"])
	info_text.text = String(info["text"])
	for child in info_facts.get_children():
		info_facts.remove_child(child)
		child.free()
	for fact: Array in info["facts"]:
		var key := _label(String(fact[0]), 15, MUTED)
		key.custom_minimum_size = Vector2(150, 0)
		key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_facts.add_child(key)
		var value := _label(String(fact[1]), 16, TEXT)
		value.custom_minimum_size = Vector2(230, 0)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_facts.add_child(value)
	info_panel.modulate.a = 0.0
	create_tween().tween_property(info_panel, "modulate:a", 1.0, 0.35)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 4 if size >= 24 else 0)
	return label


func _panel_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = border
	style.set_border_width_all(2)
	style.border_width_top = 4
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	return style


func _button(text: String, callback: Callable, icon: Texture2D = null) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = icon
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 18)
	button.add_theme_constant_override("h_separation", 8)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 17)
	for color: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(color, TEXT)
	button.add_theme_color_override("icon_normal_color", TEXT)
	button.add_theme_color_override("icon_hover_color", TEXT)
	button.add_theme_color_override("icon_pressed_color", TEXT)
	button.add_theme_stylebox_override("normal", _button_style(Brand.BLUE_HEADER))
	button.add_theme_stylebox_override("hover", _button_style(Brand.BLUE))
	button.add_theme_stylebox_override("pressed", _button_style(Brand.BLUE_DARK))
	button.pressed.connect(callback)
	return button


## Botones rectos con esquinas de 3 px, como «Comparte tu conocimiento».
func _button_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(3)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
