shader_type canvas_item;
// Camcorder view: a 1990s consumer VHS-C camcorder viewfinder. 4:3 crop, luma/chroma split
// with smeared chroma, edge-enhancement halo, snow that rises in the dark (auto gain),
// tracking wobble, head-switching noise at the bottom, interlace. `degrade` (Drift, the
// Entity nearby) makes everything worse.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float time = 0.0;
uniform float degrade = 0.0;
uniform float frame_seed = 0.0;

float h12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vn(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(h12(vec2(i, 3.1)), h12(vec2(i + 1.0, 3.1)), f * f * (3.0 - 2.0 * f));
}

vec3 to_yiq(vec3 c) {
	return vec3(dot(c, vec3(0.299, 0.587, 0.114)), dot(c, vec3(0.596, -0.274, -0.322)), dot(c, vec3(0.211, -0.523, 0.312)));
}

vec3 to_rgb(vec3 y) {
	return vec3(dot(y, vec3(1.0, 0.956, 0.621)), dot(y, vec3(1.0, -0.272, -0.647)), dot(y, vec3(1.0, -1.106, 1.703)));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float w = (4.0 / 3.0) / aspect;
	float x0 = 0.5 - w * 0.5;
	if (uv.x < x0 || uv.x > 1.0 - x0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		float lines = 480.0;
		float line = floor(uv.y * lines);
		float px = SCREEN_PIXEL_SIZE.x;
		// Tracking: slow wobble plus a rare band that drifts up the frame.
		float wob = (vn(uv.y * 6.0 + time * 0.9) - 0.5) * 0.0008 * (1.0 + degrade * 5.0);
		float band_y = fract(time * 0.035 + frame_seed * 0.0);
		float band = smoothstep(0.03, 0.0, abs(uv.y - band_y)) * (0.25 + degrade);
		wob += (h12(vec2(line, floor(time * 30.0))) - 0.5) * 0.012 * band;
		// Head-switching noise in the last lines.
		float hs = smoothstep(0.975, 0.995, uv.y);
		wob += hs * ((h12(vec2(line, floor(time * 60.0))) - 0.5) * 0.03 + 0.012);
		vec2 suv = vec2(uv.x + wob, (line + 0.5) / lines);

		// Luma: slightly soft, then edge-enhanced (the VHS halo).
		vec3 c0 = texture(screen_tex, suv).rgb;
		vec3 cl = texture(screen_tex, suv - vec2(px * 2.5, 0.0)).rgb;
		vec3 cr = texture(screen_tex, suv + vec2(px * 2.5, 0.0)).rgb;
		float y0 = to_yiq(c0).x;
		float yb = (to_yiq(cl).x + y0 * 2.0 + to_yiq(cr).x) * 0.25;
		float Y = yb + (y0 - yb) * 0.9;
		vec3 cl2 = texture(screen_tex, suv - vec2(px * 7.0, 0.0)).rgb;
		Y += (yb - to_yiq(cl2).x) * 0.12;
		// Chroma: heavily smeared horizontally and shifted right.
		vec2 iq = vec2(0.0);
		for (int k = -4; k <= 4; k++) {
			iq += to_yiq(texture(screen_tex, suv + vec2(px * (float(k) * 4.0 - 6.0), 0.0)).rgb).yz;
		}
		iq /= 9.0;
		iq *= 0.82;
		// Auto gain: in the dark the camera pumps the whole picture brighter, and snow rises with it.
		float avg = to_yiq(textureLod(screen_tex, vec2(0.5), 9.0).rgb).x;
		float gain = clamp(0.3 / max(avg, 0.02), 1.0, 2.6);
		Y *= gain;
		float gain_noise = (0.02 + 0.03 * (gain - 1.0)) * (1.0 + degrade * 2.5);
		float n = h12(vec2(floor(uv.x / px * 0.5), line) + frame_seed * 17.0) - 0.5;
		Y += n * gain_noise;
		iq += vec2(h12(vec2(line, frame_seed)) - 0.5, h12(vec2(frame_seed, line)) - 0.5) * 0.02 * (1.0 + degrade * 3.0);
		vec3 c = to_rgb(vec3(Y, iq));
		// Lifted blacks, slightly warm, interlace shimmer.
		c = c * vec3(0.93, 0.92, 0.88) + vec3(0.035, 0.03, 0.04);
		c *= 1.0 - 0.06 * mod(line + floor(frame_seed), 2.0);
		c = mix(c, vec3(h12(vec2(uv.x * 900.0, line + time))), hs * 0.5);
		// Soft lens vignette inside the 4:3 frame.
		vec2 lu = vec2((uv.x - x0) / w, uv.y) - 0.5;
		c *= 1.0 - 0.45 * smoothstep(0.12, 0.5, dot(lu, lu));
		COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
	}
}
