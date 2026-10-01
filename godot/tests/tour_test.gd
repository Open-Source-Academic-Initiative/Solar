extends SceneTree
## Prueba headless del paseo: construcción, recorrido con teclado, clic sobre
## planetas a través del viewport, fichas y pausa. Imprime SOLAR_TOUR_REPORT=<json>.

const STEP := 0.05

var checks: Array = []
var failures := 0


func _initialize() -> void:
	var packed := load("res://main.tscn") as PackedScene
	if packed == null:
		_finish({"error": "main.tscn no cargó"})
		return
	var main = packed.instantiate()  # sin tipo: se accede a miembros del script main.gd
	root.add_child(main)
	await process_frame
	await physics_frame
	await physics_frame

	var orbit_count := 0
	for child in main.get_children():
		if child is MeshInstance3D and String(child.name).begins_with("Trayectoria_"):
			orbit_count += 1
	_check(main.bodies.size() == 10, "10 cuerpos construidos (%d)" % main.bodies.size())
	_check(orbit_count == 8, "8 trayectorias (%d)" % orbit_count)
	_check(main.belt.multimesh.instance_count == 240, "240 asteroides")
	_check(main.focus_id == "", "arranca en vista general")
	_check(main.welcome_panel.visible and not main.info_panel.visible, "bienvenida visible y ficha oculta")
	_check(main.close_button != null and main.close_button.pressed.is_connected(main.quit_app), "botón Cerrar conectado a quit_app")

	var framing := {}
	var viewport_size: Vector2 = root.get_visible_rect().size
	for id: String in main.bodies:
		var p: Vector2 = main.camera.unproject_position(main.body_position(id))
		framing[id] = [roundf(p.x), roundf(p.y)]
	_check(viewport_size.x > 0.0, "viewport %s" % viewport_size)

	_key(KEY_RIGHT)
	_check(main.focus_id == "sol", "flecha derecha empieza el paseo en el Sol")
	_check(main.info_title.text == "Sol" and main.info_panel.visible, "ficha del Sol visible")
	_advance(main, 2.0)
	var d_sun: float = main.camera.global_position.distance_to(main.body_position("sol"))
	_check(absf(d_sun - 9.5) < 0.3, "tras el vuelo la cámara queda a 9,5 u del Sol (%.2f)" % d_sun)

	_key(KEY_RIGHT)
	_check(main.focus_id == "mercurio", "siguiente parada: Mercurio")
	_advance(main, 2.0)
	var d_merc: float = main.camera.global_position.distance_to(main.body_position("mercurio"))
	_check(absf(d_merc - (0.34 * 4.2 + 1.2)) < 0.3, "la cámara sigue a Mercurio en su órbita (%.2f)" % d_merc)
	_check(main.info_facts.get_child_count() == 12, "ficha de Mercurio con 6 datos (%d celdas)" % main.info_facts.get_child_count())
	_key(KEY_LEFT)
	_key(KEY_LEFT)
	_check(main.focus_id == "neptuno", "el paseo da la vuelta: antes del Sol viene Neptuno")
	_key(KEY_ESCAPE)
	_check(main.focus_id == "" and main.welcome_panel.visible, "Esc vuelve a la vista general")

	var clicks := {}
	for id: String in ["jupiter", "saturno", "tierra", "urano", "marte"]:
		main.show_overview()
		_advance(main, 2.0)
		await physics_frame
		await physics_frame
		var screen: Vector2 = main.camera.unproject_position(main.body_position(id))
		var picked: String = main.pick_at(screen)
		_click(screen)
		clicks[id] = {"screen": [roundf(screen.x), roundf(screen.y)], "raycast": picked, "focused": main.focus_id}
		_check(main.focus_id == id, "clic sobre %s lo enfoca (enfocado: '%s', rayo: '%s')" % [id, main.focus_id, picked])

	_check(main.info_title.text == "Marte", "la ficha muestra el último clic (%s)" % main.info_title.text)
	_key(KEY_SPACE)
	_advance(main, 3.0)
	var t0: float = main.sim_time
	_advance(main, 1.0)
	_check(main.paused and absf(main.sim_time - t0) < 0.01, "Espacio pausa la simulación")
	_key(KEY_SPACE)
	_advance(main, 2.0)
	_check(not main.paused and main.sim_time - t0 > 0.05, "Espacio la reanuda")

	_finish({"framing_overview_t0": framing, "clicks": clicks, "viewport": [viewport_size.x, viewport_size.y]})


func _advance(main, seconds: float) -> void:
	for i in int(round(seconds / STEP)):
		main._process(STEP)


func _key(code: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.pressed = true
	root.push_input(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.pressed = false
	root.push_input(up)


func _click(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		# `pos` viene de unproject_position, ya en coordenadas del viewport. Sin
		# in_local_coords, push_input lo trata como píxeles de la ventana headless
		# de 64x64 y lo escala x25 fuera de pantalla.
		root.push_input(ev, true)


func _check(ok: bool, label: String) -> void:
	checks.append({"ok": ok, "check": label})
	if not ok:
		failures += 1
		push_error("FALLO: " + label)


func _finish(extra: Dictionary) -> void:
	var report := {"passed": checks.size() - failures, "failed": failures, "checks": checks}
	report.merge(extra)
	print("SOLAR_TOUR_REPORT=" + JSON.stringify(report))
	print("SOLAR_TOUR_OK" if failures == 0 else "SOLAR_TOUR_FAIL")
	quit(0 if failures == 0 else 1)
