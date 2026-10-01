// Sol cartoon. La cara se dibuja en el espacio de la normal de vista, así que
// siempre mira a la cámara, como el pivote con Track To de Blender.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

uniform float blink_period = 10.0;
uniform float strength = 1.15;

const vec3 CORE = vec3(1.0, 0.888, 0.195);  // fff27a
const vec3 MID = vec3(1.0, 0.644, 0.050);  // ffd23f
const vec3 EDGE = vec3(1.0, 0.381, 0.024);  // ffa62b
const vec3 EYE = vec3(0.023, 0.008, 0.002);  // 2a1606
const vec3 BLUSH = vec3(1.0, 0.254, 0.107);  // ff8a5c

float fill(float sd) {
	float w = max(fwidth(sd), 1e-4);
	return 1.0 - smoothstep(-w, w, sd);
}

float ellipse_sd(vec2 p, vec2 c, vec2 r) {
	return (length((p - c) / r) - 1.0) * min(r.x, r.y);
}

void fragment() {
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 col = (facing < 0.55 ? CORE : (facing < 0.82 ? MID : EDGE)) * strength;

	vec2 p = NORMAL.xy;
	float tb = mod(TIME, blink_period);
	float k = clamp(1.0 - abs(tb - blink_period * 0.58) / 0.12, 0.0, 1.0);
	float ey = 1.0 - 0.92 * k;

	for (int i = 0; i < 2; i++) {
		float s = i == 0 ? -1.0 : 1.0;
		col = mix(col, BLUSH, fill(ellipse_sd(p, vec2(s * 0.53, -0.12), vec2(0.133, 0.078))));
		vec2 c = vec2(s * 0.305, 0.18);
		col = mix(col, EYE, fill(ellipse_sd(p, c, vec2(0.098, 0.14 * ey))));
		if (ey > 0.5) {
			col = mix(col, vec3(1.2), fill(length(p - c - vec2(0.035, 0.05 * ey)) - 0.035));
		}
	}

	float x = p.x;
	float sd;
	if (abs(x) < 0.305) {
		float q = x / 0.305;
		float y0 = -0.155 - 0.167 * (1.0 - q * q);
		float slope = 0.167 * 2.0 * x / (0.305 * 0.305);
		sd = abs(p.y - y0) / sqrt(1.0 + slope * slope) - 0.031;
	} else {
		sd = length(p - vec2(sign(x) * 0.305, -0.155)) - 0.031;
	}
	col = mix(col, EYE, fill(sd));
	ALBEDO = col;
}
