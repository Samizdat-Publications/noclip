shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled, depth_draw_opaque, specular_disabled;
// A portal opening (Portal, D036): shows the far side's camera image at this screen position.
// The far camera renders with the level's own environment (a camera environment override drops
// the volumetric haze in a SubViewport, S04), so its image is already exposed (fixed, exposure
// 1) and tonemapped (AgX). The main view tonemaps everything again, so this undoes the AgX curve
// (Godot 4.7 tonemap.glsl, allenwp curve and AgX matrices) to hand back scene-linear light.
// What cannot be undone: the far side's own soft-light glow (a slight extra halo on lamps).

uniform sampler2D view : filter_linear, repeat_disable;
uniform float agx_contrast = 1.3;
uniform float agx_white = 10.0;
uniform bool undo_tonemap = true;
// Measured on video (S04): the far image comes out a little darker than the place itself
// (its own soft-light glow), so a small gain closes the step at the crossing.
uniform float gain = 1.22;
uniform float desat = 0.08;

const mat3 AGX_INSET = mat3(
		vec3(0.544814746488245, 0.140416948464053, 0.0888104196149096),
		vec3(0.373787398372697, 0.754137554567394, 0.178871756420858),
		vec3(0.0813978551390581, 0.105445496968552, 0.732317823964232));
const mat3 AGX_OUTSET = mat3(
		vec3(1.96488741169489, -0.299313364904742, -0.164352742528393),
		vec3(-0.855988495690215, 1.32639796461980, -0.238183969428088),
		vec3(-0.108898916004672, -0.0270845997150571, 1.40253671195648));

float inv_awp(float y) {
	const float cp = 0.18;
	const float sm = 1.0 - cp;   // SDR output max 1.0
	float c = agx_contrast;
	float toe_a = (1.0 / cp - 1.0) * pow(cp, c);
	float den = pow(cp, c) + toe_a;
	float slope = c * pow(cp, c - 1.0) * toe_a / (den * den);
	float w = (agx_white - cp) * (agx_white - cp) / sm * slope;
	y = clamp(y, 0.0, 0.9995);
	if (y < cp) {
		return pow(toe_a * y / (1.0 - y), 1.0 / c);
	}
	float Y = y - cp;
	float a = slope / w;
	float b = slope * (1.0 - Y / sm);
	return (-b + sqrt(b * b + 4.0 * a * Y)) / (2.0 * a) + cp;
}

void fragment() {
	vec3 col = texture(view, SCREEN_UV).rgb;
	if (undo_tonemap) {
		vec3 y = inverse(AGX_OUTSET) * col;
		vec3 x = vec3(inv_awp(y.r), inv_awp(y.g), inv_awp(y.b));
		col = max(inverse(AGX_INSET) * x, vec3(0.0));
	}
	col = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), desat);
	ALBEDO = col * gain;
}
