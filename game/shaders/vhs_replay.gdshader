shader_type canvas_item;
// The death replay (S06): your last seconds played back off a worn tape in a VCR. The frames were
// recorded small (480 x 270) and are blown up soft; on top: chroma smear to the right, luma noise,
// a rolling tracking band, head-switching noise at the bottom, line jitter, faded blacks. Modes:
// 0 play, 1 rewind (picture torn by bands, fast noise), 2 pause (the frame shakes), 3 snow, 4 black.

uniform sampler2D frame_tex : filter_linear;
uniform int mode = 0;
uniform float time = 0.0;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 tape(vec2 uv) {
	// luma and chroma travel separately: chroma is softer and lags to the right
	vec3 c0 = texture(frame_tex, uv).rgb;
	vec3 cl = texture(frame_tex, uv - vec2(0.006, 0.0)).rgb;
	vec3 cl2 = texture(frame_tex, uv - vec2(0.012, 0.0)).rgb;
	float y = dot(c0, vec3(0.299, 0.587, 0.114));
	vec3 chroma = (cl + cl2) * 0.5 - vec3(dot((cl + cl2) * 0.5, vec3(0.299, 0.587, 0.114)));
	vec3 c = vec3(y) + chroma * 0.85;
	return c;
}

void fragment() {
	vec2 uv = UV;
	float t = time;
	float row = floor(uv.y * 270.0);
	vec3 col;
	if (mode == 4) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else if (mode == 3) {
		float n = hash(vec2(floor(uv.x * 480.0), row + floor(t * 60.0) * 271.0));
		float band = step(0.96, hash(vec2(row * 0.1, floor(t * 20.0))));
		col = vec3(n * 0.75 + band * 0.2);
		COLOR = vec4(col, 1.0);
	} else {
		// line jitter, more when paused or rewinding
		float jit = (hash(vec2(row, floor(t * 30.0))) - 0.5) * (mode == 0 ? 0.0025 : 0.008);
		if (mode == 2) {
			jit += sin(t * 40.0 + row * 0.3) * 0.002;
			uv.y += (hash(vec2(floor(t * 12.0), 1.0)) - 0.5) * 0.01;
		}
		// tracking band rolling down the picture
		float tb = fract(t * 0.13);
		float in_band = smoothstep(0.03, 0.0, abs(uv.y - tb));
		jit += in_band * (hash(vec2(row, t)) - 0.3) * 0.03;
		// rewind: the picture slips in a few wide horizontal bands
		if (mode == 1) {
			float bands = floor(uv.y * 6.0 + t * 9.0);
			jit += (hash(vec2(bands, floor(t * 15.0))) - 0.5) * 0.06;
		}
		uv.x += jit;
		col = tape(uv);
		// head-switching noise along the bottom
		float hs = smoothstep(0.955, 0.985, uv.y);
		uv.x += hs * (hash(vec2(row, floor(t * 30.0))) - 0.2) * 0.05;
		col = mix(col, tape(uv) * 0.6 + hash(vec2(floor(uv.x * 300.0), row + t)) * 0.3, hs);
		// noise, faded blacks, a little softening of contrast, a cool cast
		float n = hash(vec2(floor(UV.x * 480.0), row + floor(t * 30.0) * 17.0));
		col += (n - 0.5) * (mode == 1 ? 0.22 : 0.09);
		col = col * 0.88 + 0.045;
		col *= vec3(0.97, 1.0, 1.04);
		col += in_band * 0.12 * n;
		// rare white dropout specks
		col += step(0.9985, hash(vec2(floor(UV.x * 160.0), row + floor(t * 30.0)))) * 0.8;
		// scanlines
		col *= 0.93 + 0.07 * sin(UV.y * 1440.0 * 3.14159);
		// vignette
		vec2 d = UV - 0.5;
		col *= 1.0 - dot(d, d) * 0.55;
		COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
	}
}
