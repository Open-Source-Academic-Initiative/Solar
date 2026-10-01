// Contorno por casco invertido: se dibujan solo las caras traseras, infladas.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform float thickness = 0.04;
const vec3 INK = vec3(0.012, 0.010, 0.035);

void vertex() {
	VERTEX += NORMAL * thickness;
}

void fragment() {
	ALBEDO = INK;
}
