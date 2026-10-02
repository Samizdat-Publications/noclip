shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque, specular_disabled;
// A portal opening that is too far away to render (Portal, D036): dark, under the same haze as
// any distant wall, so it never shows as a black hole at the end of a hall.
#include "res://shaders/horizon.gdshaderinc"

void fragment() {
	ALBEDO = vec3(0.02, 0.018, 0.014) * horizon_fade(VERTEX);
}
