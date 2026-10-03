shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque, specular_disabled;
// A portal opening that is too far away to render live (Portal, D036). By default it is dark, under
// the same haze as any distant wall. Once the far side has been photographed (Portal.request_still,
// S05) it shows that still instead, mapped across the opening and fogged by this side's haze like
// anything else in the room, so the hall's far door reads as a lit room at the end of a dark hall.
// (Live, far views went dark: lamps fade out with distance from the camera that draws them.)
#include "res://shaders/horizon.gdshaderinc"
#include "res://shaders/agx_inverse.gdshaderinc"

uniform bool use_still = false;
uniform sampler2D still : filter_linear, repeat_disable;
uniform vec2 opening = vec2(1.16, 2.08);
uniform float gain = 1.22;
uniform float desat = 0.08;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 col = vec3(0.02, 0.018, 0.014) * horizon_fade(VERTEX);
	if (use_still) {
		vec2 uv = vec2(0.5 + lpos.z / opening.x, 0.5 - lpos.y / opening.y);
		vec3 s = agx_undo(texture(still, uv).rgb);
		s = mix(s, vec3(dot(s, vec3(0.2126, 0.7152, 0.0722))), desat);
		col = s * gain;
	}
	ALBEDO = col;
}
