// A portal opening (Portal, D036): shows the far side's camera image at this screen position.
// The far camera renders with the level's own environment (a camera environment override drops
// the volumetric haze in a SubViewport, S04), so its image is already exposed (fixed, exposure
// 1) and tonemapped (AgX). The main view tonemaps everything again, so this undoes the AgX curve
// (Godot 4.7 tonemap.glsl, allenwp curve and AgX matrices) to hand back scene-linear light.
// What cannot be undone: the far side's own soft-light glow (a slight extra halo on lamps).

uniform sampler2D view : filter_linear, repeat_disable;
#include "res://shaders/agx_inverse.gdshaderinc"
uniform bool undo_tonemap = true;
// Measured on video (S04): the far image comes out a little darker than the place itself
// (its own soft-light glow), so a small gain closes the step at the crossing.
uniform float gain = 1.22;
uniform float desat = 0.08;

void fragment() {
	vec3 col = texture(view, SCREEN_UV).rgb;
	if (undo_tonemap) {
		col = agx_undo(col);
	}
	col = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))), desat);
	ALBEDO = col * gain;
}
