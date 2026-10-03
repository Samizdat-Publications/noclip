// The live fixture field (scripts/level0/fixture_field.gd): one texel per ceiling tile holding the
// light level and tint of the panel there. Shared by the ceiling, the T-bar grid and the housings.
uniform sampler2D field_tex : filter_linear_mipmap, repeat_enable;   // shared fields wrap (S05)
uniform vec2 field_origin = vec2(0.0);
uniform float field_cell = 0.6;
uniform vec2 field_size = vec2(1.0);
uniform mat4 field_to_local = mat4(1.0);   // world -> the space's own frame (a hall is rotated to face its door, S05)

// Where a world point falls in the field's own (unrotated) frame.
vec2 field_p(vec3 w) {
	return (field_to_local * vec4(w, 1.0)).xz;
}

// Light bounced up off a lit floor fills the whole ceiling of a lit room, not just the tiles next
// to a panel (S05: the ceiling between panels read as dull gray). A wide, coarse average of the
// field, so dark rooms keep a dark ceiling.
vec3 field_bounce(vec2 p) {
	// The field's mip chain is the area average; four soft taps of a coarse level hide its blocks
	// (a 5 x 5 kernel of single texels showed as stripes on the hall's wide ceiling).
	vec2 t = (p - field_origin) / field_cell;
	vec3 acc = vec3(0.0);
	vec4 s = textureLod(field_tex, (t + vec2(1.6, 0.8)) / field_size, 2.6);
	s += textureLod(field_tex, (t + vec2(-0.8, 1.6)) / field_size, 2.6);
	s += textureLod(field_tex, (t + vec2(-1.6, -0.8)) / field_size, 2.6);
	s += textureLod(field_tex, (t + vec2(0.8, -1.6)) / field_size, 2.6);
	s *= 0.25;
	// A dead tube's orange ends only warm the tiles right next to it, not the whole ceiling: alpha
	// holds their share (S05, dark rooms' ceilings turned orange).
	return max(s.rgb - vec3(1.0, 0.36, 0.08) * s.a, vec3(0.0));
}
