// Cielo cartoon: degradado violeta con tres capas de estrellas por celdas.
shader_type sky;

#include "res://shaders/noise.gdshaderinc"

vec3 sky_gradient(float h) {
	vec3 c0 = vec3(0.0033, 0.0030, 0.0177);  // 0b0a24
	vec3 c1 = vec3(0.0070, 0.0052, 0.0396);  // 141038
	vec3 c2 = vec3(0.0160, 0.0065, 0.0685);  // 22134a
	vec3 c3 = vec3(0.0273, 0.0080, 0.0931);  // 2e1656
	if (h < 0.45) {
		return mix(c0, c1, h / 0.45);
	} else if (h < 0.75) {
		return mix(c1, c2, (h - 0.45) / 0.3);
	}
	return mix(c2, c3, (h - 0.75) / 0.25);
}

vec3 star_layer(vec3 col, vec3 d, float scale, float size, float keep, vec3 tint) {
	vec2 c = cells(d * scale);
	return (c.x < size && c.y > keep) ? tint : col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = sky_gradient(clamp(d.y * 0.5 + 0.5, 0.0, 1.0));
	col = star_layer(col, d, 70.0, 0.09, 0.55, vec3(1.0, 0.922, 0.687));
	col = star_layer(col, d, 160.0, 0.07, 0.4, vec3(0.624, 0.761, 1.0));
	col = star_layer(col, d, 32.0, 0.06, 0.8, vec3(1.0, 0.768, 0.254));
	COLOR = col;
}
