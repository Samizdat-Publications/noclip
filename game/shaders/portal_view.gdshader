shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled, depth_draw_opaque, specular_disabled;
// A portal opening (Portal, D036): shows the far side's camera image at this screen position.
// The image is scene-linear HDR, so the main view exposes and tonemaps it like everything else.

uniform sampler2D view : filter_linear, repeat_disable;

void fragment() {
	ALBEDO = texture(view, SCREEN_UV).rgb;
}
