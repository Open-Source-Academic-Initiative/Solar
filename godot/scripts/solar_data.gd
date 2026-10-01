extends RefCounted
## Parámetros y fichas del sistema solar cartoon.
##
## Los valores visuales (radio, distancia, vueltas por bucle, ángulo inicial,
## giros e inclinación) son los de
## blender/build_solar_system.py, pasados de
## Z-arriba (Blender) a Y-arriba (Godot). Tamaños y distancias no están a
## escala; las fichas sí usan datos reales.

const LOOP_SECONDS := 20.0
const SUN_RADIUS := 1.6
const BELT := Vector2(9.4, 10.1)

const TOUR := ["sol", "mercurio", "venus", "tierra", "luna", "marte",
	"jupiter", "saturno", "urano", "neptuno"]

# look: parámetros del shader toon_planet.gdshader.
#   mode 0 = bandas por latitud, 1 = manchas de ruido, 2 = color plano.
#   palette = [[posición, "rrggbb"], ...] con interpolación constante.
const BODIES := {
	"mercurio": {
		"name": "Mercurio", "radius": 0.34, "distance": 3.7, "orbits": 8,
		"start": 20.0, "spins": 4, "tilt": 0.0, "parent": "",
		"accent": "cfcad3",
		"look": {"mode": 1, "scale": 3.5,
			"palette": [[0.0, "8d8a93"], [0.52, "b3aeb8"], [0.66, "cfcad3"]],
			"craters": [5.0, 0.22, "6f6b78"]},
	},
	"venus": {
		"name": "Venus", "radius": 0.55, "distance": 5.1, "orbits": 6,
		"start": 140.0, "spins": -3, "tilt": 3.0, "parent": "",
		"accent": "f3cf7e",
		"look": {"mode": 0, "scale": 1.6, "wobble": 0.5,
			"palette": [[0.0, "e8b35a"], [0.3, "f3cf7e"], [0.55, "f8e1a0"], [0.78, "efc26a"]]},
	},
	"tierra": {
		"name": "Tierra", "radius": 0.60, "distance": 6.8, "orbits": 5,
		"start": 250.0, "spins": 10, "tilt": 23.0, "parent": "",
		"accent": "5dc15a",
		"look": {"mode": 1, "scale": 2.2,
			"palette": [[0.0, "2f7fe0"], [0.5, "3a9bf0"], [0.535, "5dc15a"], [0.64, "3e9a44"]],
			"caps": [0.84, "f4fbff"]},
	},
	"luna": {
		"name": "Luna", "radius": 0.17, "distance": 1.05, "orbits": 12,
		"start": 0.0, "spins": 12, "tilt": 0.0, "parent": "tierra",
		"accent": "d9d6e2",
		"look": {"mode": 1, "scale": 3.0,
			"palette": [[0.0, "b9b6c4"], [0.55, "d9d6e2"]],
			"craters": [4.0, 0.25, "8e8a9c"]},
	},
	"marte": {
		"name": "Marte", "radius": 0.45, "distance": 8.3, "orbits": 4,
		"start": 330.0, "spins": 10, "tilt": 25.0, "parent": "",
		"accent": "e0673a",
		"look": {"mode": 1, "scale": 3.0,
			"palette": [[0.0, "c9502e"], [0.5, "e0673a"], [0.63, "a33e25"]],
			"caps": [0.9, "fff1ea"]},
	},
	"jupiter": {
		"name": "Júpiter", "radius": 1.45, "distance": 11.8, "orbits": 3,
		"start": 60.0, "spins": 16, "tilt": 3.0, "parent": "",
		"accent": "f1b58f",
		"look": {"mode": 0, "scale": 2.5, "wobble": 0.22,
			"palette": [[0.0, "c9a27e"], [0.14, "f1dcc0"], [0.26, "c98a5b"], [0.36, "f6e7cf"],
				[0.46, "d9a071"], [0.56, "f7ead6"], [0.66, "c47f52"], [0.78, "efd7b8"], [0.9, "b98d6b"]],
			"spot": [Vector3(0.72, -0.38, 0.55), 0.24, "d9482f", "f1b58f"]},
	},
	"saturno": {
		"name": "Saturno", "radius": 1.15, "distance": 14.9, "orbits": 2,
		"start": 200.0, "spins": 14, "tilt": 24.0, "parent": "",
		"accent": "f2dca6", "rings": true,
		"look": {"mode": 0, "scale": 2.0, "wobble": 0.12,
			"palette": [[0.0, "d9b779"], [0.2, "f2dca6"], [0.35, "e2c285"], [0.5, "f7e7bd"],
				[0.66, "dcb775"], [0.82, "f0d9a2"]]},
	},
	"urano": {
		"name": "Urano", "radius": 0.85, "distance": 17.5, "orbits": 1,
		"start": 300.0, "spins": -8, "tilt": 97.0, "parent": "",
		"accent": "9fe8ea",
		"look": {"mode": 0, "scale": 1.5, "wobble": 0.1,
			"palette": [[0.0, "7fd8de"], [0.4, "9fe8ea"], [0.62, "b8f1f0"]]},
	},
	"neptuno": {
		"name": "Neptuno", "radius": 0.82, "distance": 19.7, "orbits": 1,
		"start": 110.0, "spins": 8, "tilt": 28.0, "parent": "",
		"accent": "5b8ff5",
		"look": {"mode": 0, "scale": 2.0, "wobble": 0.3,
			"palette": [[0.0, "2f5fd9"], [0.3, "4a7ef0"], [0.5, "3a68e2"], [0.72, "5b8ff5"]],
			"spot": [Vector3(0.8, 0.45, -0.3), 0.2, "1f3fa8", ""]},
	},
}

const INFO := {
	"sol": {
		"kind": "Estrella enana amarilla · centro del sistema",
		"text": "Una esfera gigante de gas caliente que produce luz y calor fusionando hidrógeno en helio. Concentra el 99,8 % de la masa del sistema solar, y su gravedad mantiene a todos los planetas en órbita.",
		"facts": [["Diámetro", "1 392 700 km (109 Tierras)"], ["Temperatura superficial", "aprox. 5 500 °C"],
			["Edad", "aprox. 4 600 millones de años"], ["Su luz llega a la Tierra en", "8 min 20 s"]],
	},
	"mercurio": {
		"kind": "Planeta rocoso · 1.º desde el Sol",
		"text": "El planeta más pequeño y el más cercano al Sol. Casi no tiene atmósfera, así que de día arde y de noche se congela. Su superficie está llena de cráteres, como la de la Luna.",
		"facts": [["Diámetro", "4 879 km"], ["Distancia al Sol", "57,9 millones de km (0,39 UA)"],
			["Año", "88 días"], ["Día solar", "176 días terrestres"], ["Lunas", "0"],
			["Temperatura", "de -180 °C a 430 °C"]],
	},
	"venus": {
		"kind": "Planeta rocoso · 2.º desde el Sol",
		"text": "Casi del tamaño de la Tierra, pero envuelto en nubes de ácido sulfúrico y una atmósfera densa de CO2 que atrapa el calor: es el planeta más caliente. Además gira al revés, y muy despacio.",
		"facts": [["Diámetro", "12 104 km"], ["Distancia al Sol", "108,2 millones de km (0,72 UA)"],
			["Año", "225 días"], ["Rotación", "243 días (retrógrada)"], ["Lunas", "0"],
			["Temperatura media", "464 °C"]],
	},
	"tierra": {
		"kind": "Planeta rocoso · 3.º desde el Sol",
		"text": "Nuestro hogar y el único lugar conocido con vida. El 71 % de su superficie es agua líquida, y su atmósfera de nitrógeno y oxígeno nos protege y regula el clima.",
		"facts": [["Diámetro", "12 742 km"], ["Distancia al Sol", "149,6 millones de km (1 UA)"],
			["Año", "365,25 días"], ["Día", "24 horas"], ["Lunas", "1"],
			["Temperatura media", "15 °C"]],
	},
	"luna": {
		"kind": "Satélite natural de la Tierra",
		"text": "Siempre nos muestra la misma cara, porque tarda lo mismo en girar sobre sí misma que en dar la vuelta a la Tierra. Su gravedad produce las mareas, y en 1969 fue el primer mundo que pisaron los humanos.",
		"facts": [["Diámetro", "3 474 km"], ["Distancia a la Tierra", "384 400 km"],
			["Vuelta a la Tierra", "27,3 días"], ["Gravedad", "1/6 de la terrestre"]],
	},
	"marte": {
		"kind": "Planeta rocoso · 4.º desde el Sol",
		"text": "El planeta rojo debe su color al óxido de hierro del suelo. Tiene casquetes polares de hielo y el volcán más alto conocido, el monte Olimpo, de unos 22 km de altura.",
		"facts": [["Diámetro", "6 779 km"], ["Distancia al Sol", "227,9 millones de km (1,52 UA)"],
			["Año", "687 días"], ["Día", "24 h 37 min"], ["Lunas", "2 (Fobos y Deimos)"],
			["Temperatura media", "-63 °C"]],
	},
	"jupiter": {
		"kind": "Gigante gaseoso · 5.º desde el Sol",
		"text": "El planeta más grande: tiene más del doble de masa que todos los demás planetas juntos. Su Gran Mancha Roja es una tormenta más grande que la Tierra que dura desde hace siglos.",
		"facts": [["Diámetro", "139 820 km"], ["Distancia al Sol", "778,5 millones de km (5,2 UA)"],
			["Año", "11,9 años terrestres"], ["Día", "9 h 56 min (el más corto)"], ["Lunas", "más de 90"],
			["Temperatura de las nubes", "-110 °C"]],
	},
	"saturno": {
		"kind": "Gigante gaseoso · 6.º desde el Sol",
		"text": "Famoso por sus anillos, hechos de miles de millones de trozos de hielo y roca. Es tan poco denso que flotaría en una piscina lo bastante grande.",
		"facts": [["Diámetro", "116 460 km"], ["Distancia al Sol", "1 434 millones de km (9,6 UA)"],
			["Año", "29,4 años terrestres"], ["Día", "10 h 34 min"], ["Lunas", "más de 270"],
			["Temperatura", "-140 °C"]],
	},
	"urano": {
		"kind": "Gigante helado · 7.º desde el Sol",
		"text": "Gira tumbado de lado, con el eje inclinado unos 98°, probablemente por un gran choque en su pasado. El metano de su atmósfera le da su color verde azulado.",
		"facts": [["Diámetro", "50 724 km"], ["Distancia al Sol", "2 871 millones de km (19,2 UA)"],
			["Año", "84 años terrestres"], ["Día", "17 h 14 min (retrógrado)"], ["Lunas", "29"],
			["Temperatura mínima", "-224 °C"]],
	},
	"neptuno": {
		"kind": "Gigante helado · 8.º desde el Sol",
		"text": "El planeta más lejano y el más ventoso: sus vientos superan los 2 000 km/h. Fue el primero descubierto con cálculos matemáticos antes de verlo con un telescopio, en 1846.",
		"facts": [["Diámetro", "49 244 km"], ["Distancia al Sol", "4 495 millones de km (30,1 UA)"],
			["Año", "164,8 años terrestres"], ["Día", "16 h 6 min"], ["Lunas", "16"],
			["Temperatura", "-200 °C"]],
	},
}
