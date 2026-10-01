// Planeta cel-shaded, sin luces: el terminador sale de dot(normal, dirección al Sol),
// con el Sol en el origen, igual que en la escena de Blender.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

#include "res://shaders/noise.gdshaderinc"

uniform sampler2D palette : source_color, filter_nearest, repeat_disable;
uniform int pattern = 0; // 0 bandas, 1 manchas, 2 plano
uniform float radius = 1.0;
uniform float noise_scale = 2.0;
uniform float wobble = 0.2;
uniform vec4 flat_color : source_color = vec4(1.0);
uniform float caps_level = 2.0; // > 1.5 desactiva los casquetes
uniform vec4 caps_color : source_color = vec4(1.0);
uniform vec3 spot_center = vec3(0.0);
uniform float spot_radius = 0.0;
uniform vec4 spot_color : source_color = vec4(1.0);
uniform float spot_ring = 0.0;
uniform vec4 spot_ring_color : source_color = vec4(1.0);
uniform float crater_scale = 0.0;
uniform float crater_size = 0.22;
uniform vec4 crater_color : source_color = vec4(0.5);

// Bandas de luz en lineal (de los hex sRGB de Blender).
const vec3 NIGHT = vec3(0.091, 0.080, 0.352);  // 5550a0
const vec3 TERMINATOR = vec3(0.456, 0.413, 0.738);  // b4acdf
const vec3 HIGHLIGHT = vec3(1.0, 0.922, 0.745);  // fff6e0
const vec3 RIM_COLOR = vec3(0.347, 0.687, 1.0);  // 9fd8ff

varying vec3 obj;
varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	obj = VERTEX / radius;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 base;
	if (pattern == 0) {
		float z = obj.y + fbm(obj * noise_scale) * wobble - wobble * 0.5;
		base = texture(palette, vec2(clamp(z * 0.5 + 0.5, 0.001, 0.999), 0.5)).rgb;
	} else if (pattern == 1) {
		base = texture(palette, vec2(clamp(fbm(obj * noise_scale), 0.001, 0.999), 0.5)).rgb;
	} else {
		base = flat_color.rgb;
	}
	if (crater_scale > 0.0) {
		vec2 c = cells(obj * crater_scale);
		if (c.y > 0.55 && c.x < crater_size) {
			base = crater_color.rgb;
		}
	}
	if (caps_level < 1.5) {
		float lat = abs(obj.y) + fbm(obj * 3.0) * 0.12;
		if (lat > caps_level) {
			base = caps_color.rgb;
		}
	}
	if (spot_radius > 0.0) {
		float d = distance(obj, spot_center);
		if (spot_ring > 0.0 && d < spot_radius * spot_ring) {
			base = spot_ring_color.rgb;
		}
		if (d < spot_radius) {
			base = spot_color.rgb;
		}
	}

	float fac = dot(normalize(wnorm), normalize(-wpos)) * 0.5 + 0.5;
	vec3 band = fac < 0.46 ? NIGHT : (fac < 0.53 ? TERMINATOR : (fac < 0.86 ? vec3(1.0) : HIGHLIGHT));
	vec3 lit = base * band;
	if (fac >= 0.86) {
		lit = mix(lit, vec3(1.0), 0.18);
	}
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	if (facing > 0.82) {
		lit = mix(lit, RIM_COLOR, 0.35);
	}
	ALBEDO = lit;
}
