#!/usr/bin/env python3
"""Procedural audio generator for Waddle Wars.

Synthesizes all SFX (mono) and music loops (stereo) as 16-bit 44.1kHz WAV
files into assets/audio/ using only the Python standard library.

Deterministic: fixed random seed 42.
Run:  python3 tools/generate_audio.py
"""

import math
import os
import random
import struct
import wave

SR = 44100
TWO_PI = math.tau
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")

rng = random.Random(42)


# ---------------------------------------------------------------------------
# Core DSP helpers
# ---------------------------------------------------------------------------

def midi_to_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def osc_sine(phase):
    return math.sin(TWO_PI * phase)


def osc_square(phase):
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def osc_saw(phase):
    return 2.0 * (phase % 1.0) - 1.0


def osc_triangle(phase):
    return 4.0 * abs((phase % 1.0) - 0.5) - 1.0


def render_tone(dur, freq_fn, wave_fn, amp_fn):
    """Phase-accumulating oscillator with time-varying freq and amplitude."""
    n = int(dur * SR)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        phase += freq_fn(t) / SR
        out[i] = wave_fn(phase) * amp_fn(t)
    return out


def adsr(t, dur, a, d, s, r):
    a = max(a, 1e-4)
    d = max(d, 1e-4)
    r = max(r, 1e-4)
    if t < 0.0 or t >= dur:
        return 0.0
    if t < a:
        return t / a
    if t < a + d:
        return 1.0 - (1.0 - s) * ((t - a) / d)
    if t < dur - r:
        return s
    return s * (dur - t) / r


def exp_decay(rate):
    return lambda t: math.exp(-rate * t)


def white_noise(dur):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(dur * SR))]


def lowpass(x, cutoff):
    """One-pole lowpass, fixed cutoff in Hz."""
    alpha = 1.0 - math.exp(-TWO_PI * cutoff / SR)
    y = 0.0
    out = [0.0] * len(x)
    for i, s in enumerate(x):
        y += alpha * (s - y)
        out[i] = y
    return out


def lowpass_sweep(x, cutoff_fn):
    """One-pole lowpass with time-varying cutoff (Hz as function of t)."""
    y = 0.0
    out = [0.0] * len(x)
    for i, s in enumerate(x):
        c = max(20.0, cutoff_fn(i / SR))
        alpha = 1.0 - math.exp(-TWO_PI * c / SR)
        y += alpha * (s - y)
        out[i] = y
    return out


def highpass(x, cutoff):
    low = lowpass(x, cutoff)
    return [a - b for a, b in zip(x, low)]


def bandpass(x, lo, hi):
    return lowpass(highpass(x, lo), hi)


def envelope(x, amp_fn):
    return [s * amp_fn(i / SR) for i, s in enumerate(x)]


def mix(*tracks):
    """Sum tracks of possibly different lengths."""
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def overlay(base, addition, start_sec, gain=1.0):
    """Add `addition` into `base` starting at start_sec, growing base if needed."""
    start = int(start_sec * SR)
    need = start + len(addition)
    if need > len(base):
        base.extend([0.0] * (need - len(base)))
    for i, s in enumerate(addition):
        base[start + i] += s * gain
    return base


def echo(x, delay_sec, feedback, taps=3):
    d = int(delay_sec * SR)
    out = list(x) + [0.0] * (d * taps)
    g = feedback
    for k in range(1, taps + 1):
        off = d * k
        for i, s in enumerate(x):
            out[i + off] += s * g
        g *= feedback
    return out

def normalize(x, peak=0.8):
    m = max((abs(s) for s in x), default=0.0)
    if m < 1e-9:
        return x
    g = peak / m
    return [s * g for s in x]


def make_loop(x, fade_sec):
    """Crossfade the tail into the head so the buffer loops seamlessly."""
    f = int(fade_sec * SR)
    n = len(x) - f
    out = x[:n]
    for i in range(f):
        w = i / f
        out[i] = out[i] * w + x[n + i] * (1.0 - w)
    return out


# ---------------------------------------------------------------------------
# WAV writing
# ---------------------------------------------------------------------------

def _pack_frames(channels):
    frames = bytearray()
    n = len(channels[0])
    for i in range(n):
        for ch in channels:
            v = max(-1.0, min(1.0, ch[i]))
            frames += struct.pack("<h", int(v * 32767))
    return bytes(frames)


def write_mono(name, samples, peak=0.8):
    samples = normalize(samples, peak)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(_pack_frames([samples]))
    print("wrote %-24s %6.2fs  peak %.2f" % (name + ".wav", len(samples) / SR, peak))


def write_stereo(name, left, right, peak=0.6):
    m = max(max(abs(s) for s in left), max(abs(s) for s in right))
    if m < 1e-9:
        m = 1.0
    g = peak / m
    left = [s * g for s in left]
    right = [s * g for s in right]
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(_pack_frames([left, right]))
    print("wrote %-24s %6.2fs  peak %.2f (stereo)" % (name + ".wav", len(left) / SR, peak))


# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

def sfx_ui_hover():
    dur = 0.05
    tick = render_tone(dur, lambda t: 1900.0, osc_sine,
                       lambda t: adsr(t, dur, 0.002, 0.03, 0.0, 0.01))
    click = envelope(highpass(white_noise(dur), 4000.0), exp_decay(140.0))
    return mix(tick, [s * 0.3 for s in click])


def sfx_ui_select():
    dur = 0.16
    a = render_tone(dur, lambda t: 880.0, osc_triangle,
                    lambda t: adsr(t, dur, 0.002, 0.1, 0.0, 0.04))
    b = render_tone(dur, lambda t: 1318.5, osc_sine,
                    lambda t: 0.5 * adsr(t, dur, 0.002, 0.08, 0.0, 0.04))
    return mix(a, b)


def sfx_countdown():
    dur = 0.16
    return render_tone(dur, lambda t: 660.0, osc_sine,
                       lambda t: adsr(t, dur, 0.004, 0.05, 0.6, 0.05))


def sfx_go():
    dur = 0.5
    out = []
    for f in (523.25, 659.26, 783.99):  # C5 E5 G5 major chord
        rise = render_tone(dur, lambda t, f=f: f * (0.94 + 0.06 * min(1.0, t / 0.06)),
                           osc_saw,
                           lambda t: adsr(t, dur, 0.004, 0.25, 0.25, 0.18))
        out.append(rise)
    stab = mix(*out)
    return lowpass(stab, 4200.0)


def sfx_jump():
    dur = 0.22
    chirp = render_tone(dur, lambda t: 400.0 + 520.0 * (t / dur) ** 0.7, osc_sine,
                        lambda t: adsr(t, dur, 0.004, 0.12, 0.3, 0.07))
    spring = render_tone(dur, lambda t: 800.0 + 1040.0 * (t / dur) ** 0.7, osc_triangle,
                         lambda t: 0.35 * adsr(t, dur, 0.004, 0.1, 0.2, 0.06))
    return mix(chirp, spring)


def sfx_land():
    thump = render_tone(0.22, lambda t: 95.0 * math.exp(-9.0 * t) + 46.0, osc_sine,
                        exp_decay(17.0))
    puff = envelope(lowpass(white_noise(0.25), 900.0), exp_decay(14.0))
    return mix(thump, [s * 0.8 for s in puff])


def sfx_slide():
    dur = 1.25
    noise = white_noise(dur)
    swoosh = lowpass_sweep(noise, lambda t: 900.0 + 700.0 * math.sin(TWO_PI * 0.8 * t))
    swoosh = highpass(swoosh, 250.0)
    shaped = envelope(swoosh, lambda t: 0.75 + 0.25 * math.sin(TWO_PI * 1.6 * t))
    return make_loop(shaped, 0.25)


def sfx_swim():
    out = [0.0]
    for k in range(3):
        t0 = k * 0.11
        f0 = 340.0 + 90.0 * k + rng.uniform(-20.0, 20.0)
        blip = render_tone(0.09, lambda t, f0=f0: f0 * (1.0 + 2.2 * t), osc_sine,
                           lambda t: adsr(t, 0.09, 0.004, 0.05, 0.2, 0.03))
        overlay(out, blip, t0, 0.9)
    swish = envelope(bandpass(white_noise(0.42), 500.0, 2600.0),
                     lambda t: adsr(t, 0.42, 0.05, 0.2, 0.3, 0.15))
    overlay(out, swish, 0.0, 0.5)
    return out


def sfx_splash():
    dur = 0.55
    body = lowpass_sweep(white_noise(dur), lambda t: 3400.0 * math.exp(-5.0 * t) + 320.0)
    body = envelope(body, lambda t: adsr(t, dur, 0.006, 0.32, 0.15, 0.18))
    droplets = [0.0]
    for _ in range(6):
        t0 = rng.uniform(0.12, 0.42)
        f0 = rng.uniform(900.0, 2100.0)
        d = render_tone(0.05, lambda t, f0=f0: f0 * (1.0 + 1.5 * t), osc_sine,
                        lambda t: adsr(t, 0.05, 0.003, 0.03, 0.0, 0.015))
        overlay(droplets, d, t0, 0.35)
    return mix(body, droplets)


def sfx_fish():
    out = [0.0]
    for i, f in enumerate((1318.5, 1760.0)):  # E6 -> A6
        note = render_tone(0.22, lambda t, f=f: f, osc_sine,
                           lambda t: adsr(t, 0.22, 0.003, 0.15, 0.0, 0.05))
        shim = render_tone(0.22, lambda t, f=f: f * 2.0, osc_sine,
                           lambda t: 0.3 * adsr(t, 0.22, 0.003, 0.1, 0.0, 0.05))
        overlay(out, mix(note, shim), i * 0.09)
    return echo(out, 0.06, 0.25, 2)


def sfx_powerup():
    notes = (523.25, 659.26, 783.99, 1046.5, 1318.5)  # C E G C E arpeggio
    out = [0.0]
    for i, f in enumerate(notes):
        n = render_tone(0.24, lambda t, f=f: f * (1.0 + 0.002 * math.sin(TWO_PI * 9.0 * t)),
                        osc_triangle,
                        lambda t: adsr(t, 0.24, 0.004, 0.16, 0.0, 0.06))
        overlay(out, n, i * 0.075)
    return echo(out, 0.09, 0.3, 2)


def sfx_powerup_use():
    whoosh = envelope(lowpass_sweep(white_noise(0.4),
                                    lambda t: 500.0 + 4200.0 * (t / 0.4) ** 2),
                      lambda t: adsr(t, 0.4, 0.05, 0.2, 0.35, 0.1))
    zap = render_tone(0.28, lambda t: 1800.0 * math.exp(-8.0 * t) + 160.0, osc_square,
                      lambda t: 0.4 * adsr(t, 0.28, 0.002, 0.2, 0.0, 0.05))
    out = [0.0]
    overlay(out, whoosh, 0.0, 0.9)
    overlay(out, lowpass(zap, 3500.0), 0.12)
    return out


def sfx_throw():
    dur = 0.32
    n = white_noise(dur)
    swept = lowpass_sweep(n, lambda t: 600.0 + 5200.0 * math.sin(math.pi * min(1.0, t / dur)))
    swept = highpass(swept, 350.0)
    return envelope(swept, lambda t: adsr(t, dur, 0.03, 0.18, 0.2, 0.08))


def sfx_snowball_hit():
    thud = render_tone(0.16, lambda t: 130.0 * math.exp(-11.0 * t) + 55.0, osc_sine,
                       exp_decay(20.0))
    poof = envelope(lowpass(white_noise(0.3), 1300.0), exp_decay(11.0))
    return mix(thud, [s * 0.85 for s in poof])


def sfx_shield_break():
    out = [0.0]
    bands = ((2400.0, 5200.0), (3600.0, 7800.0), (1600.0, 3400.0), (5000.0, 9500.0))
    for i, (lo, hi) in enumerate(bands):
        shard = envelope(bandpass(white_noise(0.3), lo, hi), exp_decay(13.0 + 3.0 * i))
        overlay(out, shard, i * 0.035, 0.9)
    for _ in range(5):
        f0 = rng.uniform(2000.0, 6500.0)
        ting = render_tone(0.12, lambda t, f0=f0: f0, osc_sine,
                           lambda t: adsr(t, 0.12, 0.002, 0.09, 0.0, 0.02))
        overlay(out, ting, rng.uniform(0.0, 0.18), 0.3)
    return out


def sfx_shove():
    dur = 0.36
    boing = render_tone(dur,
                        lambda t: (260.0 - 120.0 * (t / dur)) *
                                  (1.0 + 0.18 * math.sin(TWO_PI * 22.0 * t) * math.exp(-4.0 * t)),
                        osc_sine,
                        lambda t: adsr(t, dur, 0.004, 0.22, 0.2, 0.1))
    whack = envelope(lowpass(white_noise(0.07), 2200.0), exp_decay(55.0))
    return mix(boing, [s * 0.5 for s in whack])


def sfx_stumble():
    dur = 0.5
    wob = render_tone(dur,
                      lambda t: (420.0 - 260.0 * (t / dur)) *
                                (1.0 + 0.1 * math.sin(TWO_PI * 11.0 * t)),
                      osc_triangle,
                      lambda t: adsr(t, dur, 0.006, 0.3, 0.3, 0.15))
    return wob


def sfx_checkpoint():
    dur = 0.9
    f = 1567.98  # G6
    partials = ((1.0, 1.0, 4.0), (2.76, 0.4, 7.0), (5.40, 0.15, 10.0))
    tracks = []
    for ratio, amp, decay in partials:
        tracks.append(render_tone(dur, lambda t, r=ratio: f * r, osc_sine,
                                  lambda t, a=amp, d=decay: a * math.exp(-d * t)))
    bell = mix(*tracks)
    return envelope(bell, lambda t: adsr(t, dur, 0.002, 0.6, 0.2, 0.25))


def sfx_finish():
    out = [0.0]
    chord = (523.25, 659.26, 783.99, 1046.5)  # C major with octave
    for f in chord:
        v = render_tone(0.65, lambda t, f=f: f * (1.0 + 0.003 * math.sin(TWO_PI * 6.0 * t)),
                        osc_saw,
                        lambda t: adsr(t, 0.65, 0.01, 0.35, 0.3, 0.2))
        overlay(out, lowpass(v, 3800.0), 0.0, 0.8)
    hit = envelope(lowpass(white_noise(0.12), 3000.0), exp_decay(30.0))
    overlay(out, hit, 0.0, 0.35)
    return out


def sfx_victory():
    # Short original fanfare: C5 G4 C5 E5 G5 with final chord.
    out = [0.0]
    seq = ((523.25, 0.0, 0.18), (392.0, 0.18, 0.18), (523.25, 0.36, 0.18),
           (659.26, 0.54, 0.24), (783.99, 0.82, 0.55))
    for f, t0, d in seq:
        note = render_tone(d + 0.1, lambda t, f=f: f, osc_saw,
                           lambda t, d=d: adsr(t, d + 0.1, 0.008, d * 0.5, 0.5, 0.1))
        overlay(out, lowpass(note, 3600.0), t0, 0.7)
        shim = render_tone(d + 0.1, lambda t, f=f: f * 2.0, osc_sine,
                           lambda t, d=d: 0.25 * adsr(t, d + 0.1, 0.008, d * 0.5, 0.4, 0.1))
        overlay(out, shim, t0, 0.7)
    for f in (523.25, 659.26, 783.99, 1046.5):
        chord = render_tone(0.9, lambda t, f=f: f, osc_saw,
                            lambda t: adsr(t, 0.9, 0.01, 0.5, 0.35, 0.35))
        overlay(out, lowpass(chord, 3800.0), 1.15, 0.55)
    glk = render_tone(0.9, lambda t: 2093.0, osc_sine, exp_decay(5.0))
    overlay(out, glk, 1.15, 0.3)
    return out


def sfx_unlock():
    out = [0.0]
    notes = (1046.5, 1318.5, 1568.0, 2093.0)  # C6 E6 G6 C7
    for i, f in enumerate(notes):
        n = render_tone(0.3, lambda t, f=f: f, osc_sine,
                        lambda t: adsr(t, 0.3, 0.003, 0.2, 0.0, 0.08))
        overlay(out, n, i * 0.09)
    sparkle = envelope(highpass(white_noise(0.55), 7000.0),
                       lambda t: 0.18 * adsr(t, 0.55, 0.05, 0.35, 0.1, 0.15))
    overlay(out, sparkle, 0.05)
    return echo(out, 0.1, 0.28, 2)


def sfx_boost():
    dur = 0.75
    rocket = lowpass_sweep(white_noise(dur),
                           lambda t: 400.0 + 5600.0 * (t / dur) ** 1.5)
    rocket = envelope(rocket, lambda t: adsr(t, dur, 0.08, 0.3, 0.6, 0.2))
    rise = render_tone(dur, lambda t: 180.0 + 700.0 * (t / dur) ** 1.3, osc_triangle,
                       lambda t: 0.4 * adsr(t, dur, 0.08, 0.3, 0.5, 0.2))
    return mix(rocket, rise)


def sfx_respawn():
    out = [0.0]
    for i in range(6):
        f0 = 500.0 * (1.22 ** i)
        n = render_tone(0.35, lambda t, f0=f0: f0 * (1.0 + 0.4 * t), osc_sine,
                        lambda t: adsr(t, 0.35, 0.03, 0.2, 0.0, 0.1))
        overlay(out, n, i * 0.06, 0.55)
    return echo(out, 0.08, 0.3, 2)


def sfx_impact():
    thump = render_tone(0.2, lambda t: 110.0 * math.exp(-10.0 * t) + 48.0, osc_sine,
                        exp_decay(16.0))
    snow = envelope(lowpass(white_noise(0.22), 1100.0), exp_decay(16.0))
    return mix(thump, [s * 0.7 for s in snow])


def sfx_chirp():
    out = [0.0]
    t0 = 0.0
    for _ in range(3):
        base = rng.uniform(1150.0, 1450.0)
        span = rng.uniform(500.0, 800.0)
        d = rng.uniform(0.07, 0.1)
        c = render_tone(d,
                        lambda t, b=base, s=span, d=d: b + s * math.sin(math.pi * t / d) *
                        (1.0 + 0.08 * math.sin(TWO_PI * 38.0 * t)),
                        osc_sine,
                        lambda t, d=d: adsr(t, d, 0.006, d * 0.4, 0.4, d * 0.3))
        overlay(out, c, t0)
        t0 += d + rng.uniform(0.05, 0.09)
    return out


SFX_BUILDERS = {
    "sfx_ui_hover": (sfx_ui_hover, 0.5),
    "sfx_ui_select": (sfx_ui_select, 0.7),
    "sfx_countdown": (sfx_countdown, 0.75),
    "sfx_go": (sfx_go, 0.85),
    "sfx_jump": (sfx_jump, 0.8),
    "sfx_land": (sfx_land, 0.8),
    "sfx_slide": (sfx_slide, 0.6),
    "sfx_swim": (sfx_swim, 0.75),
    "sfx_splash": (sfx_splash, 0.8),
    "sfx_fish": (sfx_fish, 0.75),
    "sfx_powerup": (sfx_powerup, 0.8),
    "sfx_powerup_use": (sfx_powerup_use, 0.8),
    "sfx_throw": (sfx_throw, 0.75),
    "sfx_snowball_hit": (sfx_snowball_hit, 0.85),
    "sfx_shield_break": (sfx_shield_break, 0.8),
    "sfx_shove": (sfx_shove, 0.85),
    "sfx_stumble": (sfx_stumble, 0.75),
    "sfx_checkpoint": (sfx_checkpoint, 0.7),
    "sfx_finish": (sfx_finish, 0.85),
    "sfx_victory": (sfx_victory, 0.85),
    "sfx_unlock": (sfx_unlock, 0.75),
    "sfx_boost": (sfx_boost, 0.8),
    "sfx_respawn": (sfx_respawn, 0.7),
    "sfx_impact": (sfx_impact, 0.85),
    "sfx_chirp": (sfx_chirp, 0.7),
}


# ---------------------------------------------------------------------------
# Music instruments
# ---------------------------------------------------------------------------

def inst_glock(freq, dur=0.7):
    partials = ((1.0, 1.0, 5.0), (2.76, 0.3, 8.0), (5.40, 0.1, 12.0))
    tracks = []
    for ratio, amp, decay in partials:
        tracks.append(render_tone(dur, lambda t, r=ratio: freq * r, osc_sine,
                                  lambda t, a=amp, d=decay: a * math.exp(-d * t)))
    out = mix(*tracks)
    return envelope(out, lambda t: adsr(t, dur, 0.002, 0.5, 0.15, 0.15))


def inst_pluck_bass(freq, dur=0.4):
    body = render_tone(dur, lambda t: freq, osc_triangle, exp_decay(7.0))
    grit = render_tone(dur, lambda t: freq, osc_saw,
                       lambda t: 0.25 * math.exp(-10.0 * t))
    out = lowpass(mix(body, grit), 900.0)
    return envelope(out, lambda t: adsr(t, dur, 0.004, dur * 0.6, 0.3, dur * 0.25))


def inst_pad(freqs, dur):
    tracks = []
    for f in freqs:
        for det in (0.996, 1.0, 1.005):
            tracks.append(render_tone(dur, lambda t, f=f, d=det: f * d, osc_sine,
                                      lambda t: 1.0 / (3 * len(freqs))))
    out = mix(*tracks)
    return envelope(out, lambda t: adsr(t, dur, dur * 0.25, 0.05, 0.85, dur * 0.3))


def drum_kick():
    return render_tone(0.22, lambda t: 115.0 * math.exp(-26.0 * t) + 42.0, osc_sine,
                       exp_decay(19.0))


def drum_hat(open_amt=0.0):
    d = 0.05 + open_amt * 0.1
    return envelope(highpass(white_noise(d), 6500.0), exp_decay(60.0 - open_amt * 30.0))


def drum_snare():
    noise = envelope(bandpass(white_noise(0.18), 1300.0, 6500.0), exp_decay(26.0))
    tone = render_tone(0.1, lambda t: 195.0, osc_sine, exp_decay(35.0))
    return mix(noise, [s * 0.5 for s in tone])


def drum_shaker():
    return envelope(highpass(white_noise(0.07), 5000.0), exp_decay(45.0))


# ---------------------------------------------------------------------------
# Music sequencing (wrap-add keeps loops seamless: tails spill onto the start)
# ---------------------------------------------------------------------------

PENTA = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81]  # C major pentatonic, 2 octaves

CHORD_PAD = {
    "C": [48, 55, 60, 64],
    "F": [53, 60, 65, 69],
    "G": [55, 62, 67, 71],
    "Am": [45, 52, 57, 60],
}

CHORD_BASS = {"C": 36, "F": 41, "G": 43, "Am": 33}


def add_wrapped(left, right, start_sample, samples, gain, pan):
    """Pan 0.0 = hard left, 1.0 = hard right. Wraps around the loop buffer."""
    n = len(left)
    gl = gain * math.cos(pan * math.pi / 2.0)
    gr = gain * math.sin(pan * math.pi / 2.0)
    for i, s in enumerate(samples):
        idx = (start_sample + i) % n
        left[idx] += s * gl
        right[idx] += s * gr


def wrapped_echo(left, right, delay_sec, feedback, taps=3):
    n = len(left)
    d = int(delay_sec * SR)
    src_l = list(left)
    src_r = list(right)
    g = feedback
    for k in range(1, taps + 1):
        off = (d * k) % n
        # Ping-pong: swap channels each tap for width.
        a, b = (src_r, src_l) if k % 2 else (src_l, src_r)
        for i in range(n):
            j = (i + off) % n
            left[j] += a[i] * g
            right[j] += b[i] * g
        g *= feedback


def gen_melody(bars, subdiv, density, mel_rng, octave_shift=0, home=4):
    """Deterministic pentatonic walk. Returns list of (step_index, midi, length_steps)."""
    events = []
    idx = home
    steps = bars * subdiv
    step = 0
    while step < steps:
        if mel_rng.random() < density:
            idx += mel_rng.choice((-2, -1, -1, 0, 1, 1, 2))
            idx = max(0, min(len(PENTA) - 1, idx))
            length = mel_rng.choice((1, 1, 1, 2))
            # Land on strong chord tones at bar starts.
            if step % subdiv == 0 and mel_rng.random() < 0.6:
                idx = mel_rng.choice((0, 2, 5, 7))
            events.append((step, PENTA[idx] + octave_shift, length))
            step += length
        else:
            step += 1
    return events


def render_song(bpm, bars, prog, style):
    beat = 60.0 / bpm
    bar = beat * 4.0
    total = bars * bar
    n = int(round(total * SR))
    left = [0.0] * n
    right = [0.0] * n

    mel_rng = random.Random(style["seed"])

    # --- Pads: one chord per bar ------------------------------------------
    pad_cache = {}
    for b in range(bars):
        chord = prog[b]
        if chord not in pad_cache:
            pad_cache[chord] = inst_pad([midi_to_hz(m) for m in CHORD_PAD[chord]], bar * 1.05)
        pad = pad_cache[chord]
        start = int(b * bar * SR)
        add_wrapped(left, right, start, pad, style["pad_gain"], 0.35)
        add_wrapped(left, right, start + int(0.011 * SR), pad, style["pad_gain"] * 0.8, 0.65)

    # --- Bass --------------------------------------------------------------
    bass_cache = {}
    for b in range(bars):
        root = CHORD_BASS[prog[b]]
        for slot in style["bass_pattern"]:
            pos, interval = slot
            m = root + interval
            if m not in bass_cache:
                bass_cache[m] = inst_pluck_bass(midi_to_hz(m), beat * 0.9)
            start = int((b * bar + pos * beat) * SR)
            add_wrapped(left, right, start, bass_cache[m], style["bass_gain"], 0.5)

    # --- Drums -------------------------------------------------------------
    kick = drum_kick()
    snare = drum_snare()
    shaker = drum_shaker()
    hat_c = drum_hat(0.0)
    hat_o = drum_hat(0.6)
    for b in range(bars):
        bar_start = b * bar
        for pos in style["kick_beats"]:
            add_wrapped(left, right, int((bar_start + pos * beat) * SR), kick,
                        style["drum_gain"], 0.5)
        for pos in style["snare_beats"]:
            add_wrapped(left, right, int((bar_start + pos * beat) * SR), snare,
                        style["drum_gain"] * 0.8, 0.5)
        hat_step = style["hat_subdiv"]
        for k in range(int(4 * hat_step)):
            pos = k / hat_step
            sample = hat_o if (style["open_hat"] and k % int(hat_step * 2) == int(hat_step)) else hat_c
            pan = 0.38 if k % 2 == 0 else 0.62
            add_wrapped(left, right, int((bar_start + pos * beat) * SR), sample,
                        style["hat_gain"], pan)
        if style["shaker"]:
            for k in range(8):
                add_wrapped(left, right, int((bar_start + k * 0.5 * beat) * SR), shaker,
                            style["hat_gain"] * 0.5, 0.6)

    # --- Melody (glockenspiel) on its own bus, then ping-pong echo ---------
    mel_l = [0.0] * n
    mel_r = [0.0] * n
    subdiv = style["mel_subdiv"]
    step_len = bar / subdiv
    glock_cache = {}
    for step, midi, length in gen_melody(bars, subdiv, style["mel_density"], mel_rng,
                                         style["mel_octave"]):
        key = (midi, length)
        if key not in glock_cache:
            glock_cache[key] = inst_glock(midi_to_hz(midi), step_len * length + 0.35)
        start = int(step * step_len * SR)
        pan = 0.42 + 0.16 * ((step // 2) % 2)
        add_wrapped(mel_l, mel_r, start, glock_cache[key], style["mel_gain"], pan)
    wrapped_echo(mel_l, mel_r, beat * 0.75, style["echo_fb"], 3)
    for i in range(n):
        left[i] += mel_l[i]
        right[i] += mel_r[i]

    return left, right


def music_title():
    prog = ["C", "Am", "F", "G", "C", "Am", "F", "G", "F", "G"]
    style = {
        "seed": 4201,
        "pad_gain": 0.5,
        "bass_gain": 0.55,
        "bass_pattern": [(0.0, 0), (2.0, 0), (3.0, 7)],
        "drum_gain": 0.4,
        "kick_beats": [0.0],
        "snare_beats": [],
        "hat_subdiv": 1.0,
        "hat_gain": 0.14,
        "open_hat": False,
        "shaker": True,
        "mel_subdiv": 8,
        "mel_density": 0.5,
        "mel_octave": 0,
        "mel_gain": 0.5,
        "echo_fb": 0.32,
    }
    return render_song(100, 10, prog, style)  # 10 bars @ 100 BPM = 24.0s


def music_race():
    prog = ["C", "C", "F", "F", "Am", "Am", "G", "G"] * 2
    style = {
        "seed": 4202,
        "pad_gain": 0.4,
        "bass_gain": 0.6,
        "bass_pattern": [(0.0, 0), (0.5, 0), (1.0, 7), (1.5, 0),
                         (2.0, 0), (2.5, 0), (3.0, 7), (3.5, 12)],
        "drum_gain": 0.5,
        "kick_beats": [0.0, 2.0],
        "snare_beats": [1.0, 3.0],
        "hat_subdiv": 2.0,
        "hat_gain": 0.16,
        "open_hat": True,
        "shaker": False,
        "mel_subdiv": 8,
        "mel_density": 0.68,
        "mel_octave": 0,
        "mel_gain": 0.5,
        "echo_fb": 0.28,
    }
    return render_song(120, 16, prog, style)  # 16 bars @ 120 BPM = 32.0s


def music_final():
    prog = ["Am", "Am", "F", "F", "C", "C", "G", "G"]
    style = {
        "seed": 4203,
        "pad_gain": 0.42,
        "bass_gain": 0.62,
        "bass_pattern": [(0.0, 0), (0.5, 0), (1.0, 0), (1.5, 7),
                         (2.0, 0), (2.5, 0), (3.0, 12), (3.5, 7)],
        "drum_gain": 0.55,
        "kick_beats": [0.0, 1.0, 2.0, 3.0],
        "snare_beats": [1.0, 3.0, 3.75],
        "hat_subdiv": 4.0,
        "hat_gain": 0.13,
        "open_hat": True,
        "shaker": False,
        "mel_subdiv": 16,
        "mel_density": 0.55,
        "mel_octave": 12,
        "mel_gain": 0.45,
        "echo_fb": 0.24,
    }
    return render_song(120, 8, prog, style)  # 8 bars @ 120 BPM = 16.0s


MUSIC_BUILDERS = {
    "music_title": music_title,
    "music_race": music_race,
    "music_final": music_final,
}


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def verify_all():
    print("\n--- verification -----------------------------------------------")
    failures = []
    for name in sorted(list(SFX_BUILDERS) + list(MUSIC_BUILDERS)):
        path = os.path.join(OUT_DIR, name + ".wav")
        if not os.path.isfile(path):
            failures.append("%s: missing" % name)
            continue
        with wave.open(path, "rb") as w:
            ch = w.getnchannels()
            frames = w.getnframes()
            rate = w.getframerate()
            raw = w.readframes(frames)
        dur = frames / rate
        count = frames * ch
        vals = struct.unpack("<%dh" % count, raw)
        peak = max(abs(v) for v in vals) / 32767.0
        rms = math.sqrt(sum(v * v for v in vals) / count) / 32767.0
        status = "ok"
        if dur < 0.03:
            status = "TOO SHORT"
        elif rms < 0.004:
            status = "NEAR SILENT"
        elif peak > 0.86:
            status = "TOO HOT"
        if status != "ok":
            failures.append("%s: %s (dur=%.2fs rms=%.4f peak=%.3f)" %
                            (name, status, dur, rms, peak))
        print("%-22s %dch %6.2fs  rms %.4f  peak %.3f  %s" %
              (name, ch, dur, rms, peak, status))
    if failures:
        raise SystemExit("FAILED:\n" + "\n".join(failures))
    print("all %d files verified" % (len(SFX_BUILDERS) + len(MUSIC_BUILDERS)))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("--- sfx --------------------------------------------------------")
    for name, (builder, peak) in SFX_BUILDERS.items():
        write_mono(name, builder(), peak)
    print("--- music ------------------------------------------------------")
    for name, builder in MUSIC_BUILDERS.items():
        l, r = builder()
        write_stereo(name, l, r, 0.6)
    verify_all()


if __name__ == "__main__":
    main()
