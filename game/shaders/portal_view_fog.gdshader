shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque, specular_disabled;
// The same portal view under this side's haze (S05): used for the hall's far door when you are more
// than a few meters away, so the lit air in front of it covers the doorway too, the same way it
// covers the still that stands in for it further out (Portal.request_still).
#include "res://shaders/portal_view.gdshaderinc"
