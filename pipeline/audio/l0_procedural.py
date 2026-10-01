"""Procedural synthesis for Level 0: fixture hum, failing tube buzz, room tone, tube ticks, camcorder.
Every loop is built from integer-cycle sinusoids and FFT-periodic noise so the seam is exact."""
import numpy as np
from l0_lib import SR, tvec, pnoise, band, tilt, softclip, circ_conv_add, butter, fade

TWO_PI = 2 * np.pi


# ------------------------------------------------------------------ fixture hum (8.0 s)
HUM_PARAMS = {
    "a": dict(seed=1001, harm={60: 0.05, 120: 1.0, 180: 0.16, 240: 0.42, 300: 0.09, 360: 0.26,
                               480: 0.17, 600: 0.10},
              buzz=0.05, buzz_band=(1800, 6500), rough=0.02, wobble=(0.030, 0.018)),
    "b": dict(seed=2002, harm={60: 0.07, 120: 1.0, 180: 0.24, 240: 0.62, 300: 0.15, 360: 0.45,
                               480: 0.34, 600: 0.24, 720: 0.14, 840: 0.08},
              buzz=0.085, buzz_band=(2200, 8000), rough=0.03, wobble=(0.040, 0.022)),
}


def hum(variant):
    p = HUM_PARAMS[variant]
    rng = np.random.default_rng(p["seed"])
    dur = 8.0
    n = int(dur * SR)
    t = tvec(n)
    x = np.zeros(n)
    for f, a in p["harm"].items():
        assert abs(f * dur - round(f * dur)) < 1e-9  # integer cycles
        x += a * np.sin(TWO_PI * f * t + rng.uniform(0, TWO_PI))
    # whole-cycle slow wobble (0.125 Hz and 0.375 Hz)
    w = 1 + p["wobble"][0] * np.sin(TWO_PI * 1 * t / dur + rng.uniform(0, TWO_PI)) \
          + p["wobble"][1] * np.sin(TWO_PI * 3 * t / dur + rng.uniform(0, TWO_PI))
    x *= w
    # tube buzz: HF filtered noise amplitude-modulated at 120 Hz
    lo, hi = p["buzz_band"]
    am = (0.5 + 0.5 * np.cos(TWO_PI * 120 * t + rng.uniform(0, TWO_PI))) ** 2
    x += p["buzz"] * pnoise(n, band(lo, hi, 18), rng) * (0.35 + am)
    # faint low-mid roughness (core vibration)
    x += p["rough"] * pnoise(n, band(100, 900, 18), rng)
    return x


# ------------------------------------------------------------------ failing tube buzz (6.0 s)
def failing_buzz(seed=3003):
    rng = np.random.default_rng(seed)
    dur = 6.0
    n = int(dur * SR)
    t = tvec(n)
    # irregular slow envelopes (periodic noise, <10 Hz)
    slow = pnoise(n, band(0.2, 7, 30), rng)
    slow = slow / np.max(np.abs(slow))
    # rough harmonic stack on 120 Hz, many partials, flat-ish -> raspy
    stack = np.zeros(n)
    for k in range(1, 26):
        f = 120 * k
        stack += (1.0 / k ** 0.45) * np.sin(TWO_PI * f * t + rng.uniform(0, TWO_PI))
    stack *= 0.10 * (1 + 0.45 * slow)
    # sizzle: high-mid noise, gated chaotically, AM at 120 Hz
    hf = pnoise(n, band(1500, 6500, 18), rng)
    gate = np.clip(0.55 + 1.1 * pnoise(n, band(0.3, 25, 24), rng) * 0.5, 0.05, 1.6)
    am120 = 0.45 + 0.55 * np.abs(np.cos(TWO_PI * 120 * t / 2 + rng.uniform(0, 6.28)))
    sizzle = 0.55 * hf * gate * am120
    mid = 0.25 * pnoise(n, band(500, 2200, 18), rng) * (0.6 + 0.4 * slow)
    x = stack + sizzle + mid
    # crackle: Poisson clicks (wrapped around the loop end)
    crack = np.zeros(n)
    n_clicks = int(rng.poisson(60))
    for _ in range(n_clicks):
        pos = int(rng.integers(0, n))
        ln = int(rng.uniform(0.0008, 0.006) * SR)
        e = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln * rng.uniform(0.12, 0.35)))
        e = butter(e, "high", rng.uniform(1500, 3500), 2)
        circ_conv_add(crack, pos, e * rng.lognormal(-0.2, 0.7) * 1.2)
    # a few louder arcs: 25-70 ms sparks
    for _ in range(5):
        pos = int(rng.integers(0, n))
        ln = int(rng.uniform(0.025, 0.07) * SR)
        tt = np.arange(ln) / SR
        e = rng.standard_normal(ln) * np.exp(-tt / rng.uniform(0.01, 0.025))
        e = butter(e, "high", 2200, 2) * (0.5 + 0.5 * np.cos(TWO_PI * 120 * tt))
        circ_conv_add(crack, pos, e * rng.uniform(1.6, 2.6))
    x = x + crack
    return softclip(x * 0.5, 1.2)


# ------------------------------------------------------------------ room tone (30 s, stereo)
def room_tone(seed=4004):
    rng = np.random.default_rng(seed)
    dur = 30.0
    n = int(dur * SR)
    t = tvec(n)
    # low rumble: shared between channels (long wavelengths), very low
    rumble = pnoise(n, band(22, 75, 18), rng)
    chans = []
    for c in range(2):
        hvac = pnoise(n, band(90, 520, 12), rng)           # distant air handling
        air = pnoise(n, tilt(800, 6000, -9), rng)           # faint air hiss
        # slow breathing, whole cycles over 30 s, distinct per channel, shallow so nothing stands out
        br = 1.0
        for k, d in ((2, 0.06), (3, 0.05), (5, 0.035), (7, 0.02)):
            br = br + d * np.sin(TWO_PI * k * t / dur + rng.uniform(0, TWO_PI))
        ch = 0.9 * rumble + 0.55 * hvac * br + 0.12 * air * br
        chans.append(ch)
    return np.stack(chans, axis=1)


# ------------------------------------------------------------------ tube tick one-shots
def tube_tick(seed):
    rng = np.random.default_rng(seed)
    n = int(0.40 * SR)
    t = tvec(n)
    x = np.zeros(n)
    # metallic tink: inharmonic damped modes of the tube cap / fixture sheet metal
    base = rng.uniform(0.9, 1.12)
    modes = [(2310, 1.0, 0.018), (3720, 0.7, 0.012), (6140, 0.5, 0.008), (8850, 0.3, 0.005)]
    t0 = int(0.003 * SR)
    for f, a, tau in modes:
        f *= base * rng.uniform(0.97, 1.03)
        tau *= rng.uniform(0.7, 1.4)
        tt = t[: n - t0]
        x[t0:] += a * np.exp(-tt / tau) * np.sin(TWO_PI * f * tt + rng.uniform(0, 6.28))
    # contact click
    cl = int(0.0009 * SR)
    clk = butter(rng.standard_normal(cl), "high", 1800, 2) * np.hanning(cl)
    x[t0:t0 + cl] += 1.5 * clk
    # starter zap: short gated noise burst AM'd at 120 Hz + a few sparks
    z0 = int(rng.uniform(0.012, 0.030) * SR)
    zl = int(rng.uniform(0.035, 0.075) * SR)
    zt = np.arange(zl) / SR
    zap = butter(rng.standard_normal(zl), "high", 1800, 2)
    zap = butter(zap, "low", 9000, 2)
    zap *= np.exp(-zt / rng.uniform(0.012, 0.03)) * (0.45 + 0.55 * np.abs(np.cos(TWO_PI * 60 * zt)))
    x[z0:z0 + zl] += 0.9 * zap
    for _ in range(rng.integers(2, 5)):
        p = z0 + int(rng.uniform(0, zl))
        ln = int(0.0007 * SR)
        x[p:p + ln] += rng.uniform(0.5, 1.2) * butter(rng.standard_normal(ln), "high", 3000, 2)
    # faint second try (the tube fails to strike and clicks again)
    if seed % 2 == 0:
        p = int(rng.uniform(0.09, 0.16) * SR)
        ln = int(0.05 * SR)
        tt = np.arange(ln) / SR
        x[p:p + ln] += 0.35 * np.exp(-tt / 0.012) * np.sin(TWO_PI * 3300 * base * tt)
    # trim tail & fade
    x = x[: int(0.32 * SR)]
    return fade(x, 0.0, 40)


# ------------------------------------------------------------------ camcorder
def cam_beep():
    n = int(0.14 * SR)
    t = tvec(n)
    f = 2800.0
    # piezo-ish: square-ish (odd harmonics, bandlimited) with a bit of 2nd resonance
    x = np.zeros(n)
    for k in (1, 3, 5, 7):
        x += np.sin(TWO_PI * f * k * t) / k
    x += 0.25 * np.sin(TWO_PI * 5600 * t)
    env = np.ones(n)
    a = int(0.002 * SR)
    r = int(0.018 * SR)
    env[:a] = np.linspace(0, 1, a)
    env[-r:] = np.linspace(1, 0, r)
    return x * env


def cam_motor(seed=5005):
    rng = np.random.default_rng(seed)
    dur = 4.0
    n = int(dur * SR)
    t = tvec(n)
    x = np.zeros(n)
    # capstan/drum motor fundamental + harmonics (integer cycles in 4 s)
    for f, a in ((50, 1.0), (100, 0.55), (150, 0.35), (200, 0.2), (300, 0.12)):
        x += a * np.sin(TWO_PI * f * t + rng.uniform(0, 6.28))
    # tape-belt flutter: 7 Hz amplitude, 3 Hz slower drift
    x *= 1 + 0.06 * np.sin(TWO_PI * 28 * t / dur + 1.0) + 0.03 * np.sin(TWO_PI * 12 * t / dur + 2.0)
    # servo whine (FM, whole cycles)
    x += 0.10 * np.sin(TWO_PI * 2400 * t + 1.5 * np.sin(TWO_PI * 8 * t / dur * 3))
    # head-drum rub / gear noise
    x += 0.32 * pnoise(n, band(800, 5000, 12), rng) * (0.7 + 0.3 * np.sin(TWO_PI * 30 * t))
    x += 0.15 * pnoise(n, band(120, 600, 12), rng)
    return x
