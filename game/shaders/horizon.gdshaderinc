// The horizon (DECISIONS D020): every surface fades into the dark haze between HZ_BEGIN and
// HZ_END meters from the eye, so chunks streamed in further out never pop into view, and the
// identical copies of a loop corridor look the same from whichever copy you stand in.
const float HZ_BEGIN = 34.0;
const float HZ_END = 46.0;

float horizon_fade(vec3 view_pos) {
	return 1.0 - smoothstep(HZ_BEGIN, HZ_END, length(view_pos));
}
