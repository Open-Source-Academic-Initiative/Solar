// Anillos de Saturno sobre un plano: bandas constantes, división de Cassini y
// bordes de tinta.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float inner = 1.5;
uniform float outer = 2.6;
uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
const vec3 INK = vec3(0.012, 0.010, 0.035);

varying vec3 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float rel = (length(lp.xz) - inner) / (outer - inner);
	if (rel < 0.0 || rel > 1.0 || (rel > 0.58 && rel < 0.63)) {
		discard;
	}
	vec3 c = texture(palette, vec2(clamp(rel, 0.001, 0.999), 0.5)).rgb;
	if (rel < 0.02 || rel > 0.98) {
		c = INK;
	}
	ALBEDO = c;
}
