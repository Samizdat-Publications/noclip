shader_type spatial;
render_mode unshaded, cull_back, fog_disabled, shadows_disabled, depth_draw_never, blend_mix;
// What the naked eye gets of the Occupant when it hunts (S06, L156; VISION: "to the naked eye it is
// an absence"): no body, only the room behind it bent a little out of place, as if the picture there
// were a frame behind, the wallpaper's pattern jumping where it stands. It also throws a shadow
// (a separate shadow-only copy), so in the light you see the shadow of something that is not there.

#include "res://shaders/occupant_common.gdshaderinc"
#include "res://shaders/horizon.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float presence = 1.0;      // 0 nothing, 1 the full bend
uniform float darken = 0.2;

varying vec3 mpos;

void vertex() {
	vec3 p = (to_body * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize(mat3(to_body) * NORMAL);
	float id;
	float f;
	p = occ_displace(p, n, id, f);
	mpos = p;
	VERTEX = (from_body * vec4(p, 1.0)).xyz;
}

void fragment() {
	float hz = horizon_fade(VERTEX);
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	// The picture slips sideways in bands (like the tape's tearing, but in the room itself), more
	// toward the outline so the shape reads as an edge, not a blob.
	float band = floor(mpos.y / 0.06);
	float st = floor(time * 12.0);
	float sx = (n_hash12(vec2(band, st)) - 0.5) * 0.006 + (n_value(vec2(mpos.y * 6.0, time * 2.0)) - 0.5) * 0.004;
	vec2 bend = NORMAL.xy * 0.0035 * (0.2 + rim) + vec2(sx, 0.0);
	vec3 bg = textureLod(screen_tex, SCREEN_UV + bend * presence, 0.0).rgb;
	// A trace of darkness where it stands, strongest at the head and the outline.
	float head = smoothstep(height * 0.78, height * 0.9, mpos.y);
	float dk = darken * (0.4 + 0.6 * rim + head * 0.5) * presence;
	ALBEDO = bg * (1.0 - dk);
	ALPHA = clamp(presence * hz, 0.0, 1.0);
}
