shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
// The red light an exit sign spills onto the wall round its box (Stewart, S04): a soft rounded
// glow, strongest just outside the box edge, fading out over a few centimeters to half a meter.
#include "res://shaders/horizon.gdshaderinc"

uniform vec3 color : source_color = vec3(1.0, 0.22, 0.12);
uniform float strength = 0.07;

void fragment() {
	vec2 q = (UV - 0.5) * vec2(1.1, 0.7);          // meters from the middle
	vec2 box = vec2(0.22, 0.115);                  // half size of the sign box
	vec2 d = max(abs(q) - box, vec2(0.0));
	float r = length(d);
	float g = exp(-r * 9.0);   // inside the box outline it sits behind the box anyway
	float edge = min(0.55 - abs(q.x), 0.35 - abs(q.y));
	g *= smoothstep(0.0, 0.14, edge);   // nothing left at the quad's border
	ALBEDO = color * strength * g * horizon_fade(VERTEX);
}
