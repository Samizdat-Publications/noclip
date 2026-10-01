class_name NoiseUtil
extends RefCounted
## CPU mirror of shaders/common_noise.gdshaderinc, so gameplay (footsteps on wet carpet,
## bots avoiding puddles) agrees with what the shaders draw.


static func _fract(x: float) -> float:
	return x - floorf(x)


static func hash12(p: Vector2) -> float:
	var p3 := Vector3(_fract(p.x * 0.1031), _fract(p.y * 0.1031), _fract(p.x * 0.1031))
	var d := p3.dot(Vector3(p3.y, p3.z, p3.x) + Vector3(33.33, 33.33, 33.33))
	p3 += Vector3(d, d, d)
	return _fract((p3.x + p3.y) * p3.z)


static func value(p: Vector2) -> float:
	var i := Vector2(floorf(p.x), floorf(p.y))
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := hash12(i)
	var b := hash12(i + Vector2(1, 0))
	var c := hash12(i + Vector2(0, 1))
	var d := hash12(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func fbm(p: Vector2, octaves: int = 5) -> float:
	var s := 0.0
	var a := 0.5
	for i in octaves:
		s += a * value(p)
		p = p * 2.03 + Vector2(17.1, 9.2)
		a *= 0.5
	return s
