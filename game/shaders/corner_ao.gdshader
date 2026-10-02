shader_type spatial;
render_mode unshaded, blend_mul, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Corner occlusion (L093, D031): thin strips laid where surfaces meet (wall and floor, wall and
// ceiling, inner wall corners) darken the lit image toward the crease, the way a baked AO pass
// would. UV.y runs from the crease (0) outward (1). Multiplies what is behind it, so it works
// under any light, and fades out with the haze so it never shows past the horizon.

#include "res://shaders/horizon.gdshaderinc"

uniform float strength = 0.55;
uniform float power = 1.6;

void fragment() {
	float t = clamp(UV.y, 0.0, 1.0);
	float occ = pow(1.0 - t, power) * strength * horizon_fade(VERTEX);
	ALBEDO = vec3(1.0 - occ);
}
