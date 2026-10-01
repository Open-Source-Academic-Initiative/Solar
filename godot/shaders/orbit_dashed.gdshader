// Trayectoria punteada: guiones por ángulo alrededor del eje Y.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float dashes = 40.0;
const vec3 DASH_COLOR = vec3(0.192, 0.502, 0.761) * 0.8;  // azul OpenSAI 3180c2 x 0.8

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	if (sin(atan(lp.z, lp.x) * dashes) < -0.1) {
		discard;
	}
	ALBEDO = DASH_COLOR;
}
