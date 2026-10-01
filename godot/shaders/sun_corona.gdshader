// Corona de rayos con contorno y halo suave, en un quad que siempre mira a la
// cámara y gira una vez por bucle.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform float sun_radius = 1.6;
uniform float half_size = 4.16;
uniform float period = 20.0;
uniform float points = 14.0;

const vec3 RAY_IN = vec3(1.0, 0.644, 0.050);  // ffd23f
const vec3 RAY_OUT = vec3(1.0, 0.434, 0.027);  // ffb02e
const vec3 HALO = vec3(1.0, 0.761, 0.195);  // ffe27a
const vec3 INK = vec3(0.012, 0.010, 0.035);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
			INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

float star_radius(float a, float r_in, float r_out) {
	float seg = PI / points;
	float t = mod(a, 2.0 * seg);
	float r1 = r_out;
	float r2 = r_in;
	if (t > seg) {
		r1 = r_in;
		r2 = r_out;
		t -= seg;
	}
	return r1 * r2 * sin(seg) / (r1 * sin(t) + r2 * sin(seg - t));
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * half_size;
	float r = length(p);
	float a = mod(atan(p.y, p.x) + TIME * TAU / period, TAU);
	float R = sun_radius;
	float w = max(fwidth(r), 1e-4);
	float in_ray = 1.0 - smoothstep(-w, w, r - star_radius(a, R * 1.12, R * 1.55));
	float in_ink = 1.0 - smoothstep(-w, w, r - star_radius(a, R * 1.16, R * 1.62));
	vec3 ray = (r / (R * 1.6) < 0.82 ? RAY_IN : RAY_OUT) * 1.1;
	float h = r / (R * 2.6);
	float halo = h < 0.5 ? 0.32 : (h < 0.62 ? mix(0.32, 0.12, (h - 0.5) / 0.12)
			: mix(0.12, 0.0, clamp((h - 0.62) / 0.38, 0.0, 1.0)));
	vec3 col = mix(mix(HALO, INK, in_ink), ray, in_ray);
	ALBEDO = col;
	ALPHA = max(in_ink, halo);
}
