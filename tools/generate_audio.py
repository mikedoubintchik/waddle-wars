#!/usr/bin/env python3
"""Procedural audio generator for Waddle Wars.

Synthesizes every sound effect (mono 16-bit WAV) and every music loop
(stereo, encoded to OGG Vorbis) into assets/audio/ using only the Python
standard library.  ffmpeg is used for the final WAV->OGG encode of music.

Design rules this file follows (they are what separates "cheap" from
"finished" game audio):

  * Every SFX is LAYERED.  Minimum of three elements: a transient (the first
    3-15 ms, which is what makes a sound feel physical), a body (the pitched
    or resonant part that says what the object is), and a tail (noise / air /
    room that says where it happened).
  * Every SFX MOVES.  Pitch envelopes, filter envelopes, or both.  A static
    timbre is the single loudest tell of a synthesised placeholder.
  * Every SFX is PHYSICALLY MOTIVATED.  Snow is pink noise through a closing
    lowpass.  Ice is bright bandpassed noise plus comb resonance.  Water is a
    resonant filter with rising bubble chirps.  Penguins are formant-filtered
    pulse waves.
  * Loudness is matched by short-term RMS (loudest 150 ms window), not by
    peak, so nothing jumps out.  UI sits ~8 dB under gameplay.
  * Music has sub bass, a real drum kit, motif-based melodies (not random
    walks) and an A/B arrangement, and stays seamlessly loopable via
    wrap-around note tails.

Deterministic: fixed seeds.
Run:  python3 tools/generate_audio.py
"""

import cmath
import math
import os
import random
import shutil
import struct
import subprocess
import wave

SR = 44100
TWO_PI = math.tau
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")

rng = random.Random(42)

# Filled in by the writers, consumed by verify_all().
MEASURED = {}


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


def osc_pulse(width):
    """Variable-width pulse; narrow widths read as 'chip lead'."""
    return lambda phase: 1.0 if (phase % 1.0) < width else -1.0


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


def punch(attack, rate, curve=1.0):
    """Percussive envelope: near-instant attack, exponential fall.

    `attack` in seconds keeps the very first samples from clicking while still
    reading as instantaneous; `curve` > 1 makes the decay snappier up front.
    """
    def fn(t):
        if t < attack:
            return (t / attack) ** 0.5
        e = math.exp(-rate * (t - attack))
        return e ** curve
    return fn


def white_noise(dur):
    return [rng.uniform(-1.0, 1.0) for _ in range(int(dur * SR))]


def pink_noise(dur):
    """Paul Kellet's economy pink filter. Snow, wind and cloth are pink, not
    white -- white noise is the classic 'cheap synth' hiss."""
    n = int(dur * SR)
    out = [0.0] * n
    b0 = b1 = b2 = 0.0
    for i in range(n):
        w = rng.uniform(-1.0, 1.0)
        b0 = 0.99765 * b0 + w * 0.0990460
        b1 = 0.96300 * b1 + w * 0.2965164
        b2 = 0.57000 * b2 + w * 1.0526913
        out[i] = (b0 + b1 + b2 + w * 0.1848) * 0.32
    return out


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


def svf(x, cutoff_fn, q=1.0, mode="lp"):
    """Chamberlin state-variable filter: 12 dB/oct with resonance.

    This is the workhorse for filter *movement* -- a resonant sweep is what
    makes a whoosh sound like air rather than like noise being faded.
    `cutoff_fn` may be a constant or a function of t.
    """
    if not callable(cutoff_fn):
        c = float(cutoff_fn)
        cutoff_fn = lambda t: c
    damp = 1.0 / max(0.5, q)
    low = 0.0
    band = 0.0
    out = [0.0] * len(x)
    for i, s in enumerate(x):
        fc = min(6800.0, max(20.0, cutoff_fn(i / SR)))
        f = 2.0 * math.sin(math.pi * fc / SR)
        # Two passes at half coefficient = cleaner response, less aliasing.
        for _ in range(2):
            low += f * band
            high = s - low - damp * band
            band += f * high
        if mode == "lp":
            out[i] = low
        elif mode == "bp":
            out[i] = band
        else:
            out[i] = high
    return out


def comb(x, freq, feedback, damp=0.3, tail=0.0):
    """Feedback comb -> metallic/tuned resonance. Used for ice and shards."""
    d = max(2, int(SR / freq))
    n = len(x) + int(tail * SR)
    buf = [0.0] * d
    out = [0.0] * n
    lp = 0.0
    for i in range(n):
        s = x[i] if i < len(x) else 0.0
        v = buf[i % d]
        lp += (1.0 - damp) * (v - lp)
        out[i] = s + lp
        buf[i % d] = out[i] * feedback
    return out


def allpass(x, delay_samples, g=0.5):
    d = max(1, delay_samples)
    buf = [0.0] * d
    out = [0.0] * len(x)
    for i, s in enumerate(x):
        v = buf[i % d]
        y = -g * s + v
        buf[i % d] = s + g * y
        out[i] = y
    return out


_REVERB_COMBS = (1557, 1617, 1491, 1422)


def reverb(x, room=0.82, damp=0.35, wet=0.25, predelay=0.008, tail=0.7):
    """Small Schroeder reverb. Space is the cheapest way to stop a sound
    feeling like it was pasted on top of the mix."""
    pre = int(predelay * SR)
    n = len(x) + int(tail * SR)
    src = [0.0] * pre + list(x) + [0.0] * (n - len(x))
    src = src[:n]
    acc = [0.0] * n
    for d in _REVERB_COMBS:
        buf = [0.0] * d
        lp = 0.0
        for i in range(n):
            v = buf[i % d]
            lp += (1.0 - damp) * (v - lp)
            y = src[i] + lp * room
            buf[i % d] = y
            acc[i] += v * 0.25
    acc = allpass(acc, 225, 0.5)
    acc = allpass(acc, 556, 0.5)
    out = [0.0] * n
    for i in range(n):
        dry = x[i] if i < len(x) else 0.0
        out[i] = dry + acc[i] * wet
    return out


def envelope(x, amp_fn):
    return [s * amp_fn(i / SR) for i, s in enumerate(x)]


def gain(x, g):
    return [s * g for s in x]


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


def dc_block(x):
    """One-pole DC blocker; keeps sub-heavy layers from eating headroom."""
    out = [0.0] * len(x)
    xp = 0.0
    yp = 0.0
    for i, s in enumerate(x):
        y = s - xp + 0.9995 * yp
        out[i] = y
        xp = s
        yp = y
    return out


def soft_clip(x, ceiling):
    """tanh-style saturating limiter. Rounds transients instead of shredding
    them and keeps the true peak below `ceiling`."""
    return [ceiling * math.tanh(s / ceiling) for s in x]


def normalize(x, peak=0.8):
    m = max((abs(s) for s in x), default=0.0)
    if m < 1e-9:
        return x
    g = peak / m
    return [s * g for s in x]


def fade_edges(x, fade_in=0.0005, fade_out=0.006):
    fi = max(1, int(fade_in * SR))
    fo = max(1, int(fade_out * SR))
    n = len(x)
    for i in range(min(fi, n)):
        x[i] *= i / fi
    for i in range(min(fo, n)):
        x[n - 1 - i] *= i / fo
    return x


def make_loop(x, fade_sec):
    """Crossfade the tail into the head so the buffer loops seamlessly."""
    f = int(fade_sec * SR)
    n = len(x) - f
    out = x[:n]
    for i in range(f):
        w = i / f
        out[i] = out[i] * w + x[n + i] * (1.0 - w)
    return out


def short_rms(x, win=0.15):
    """Loudest short-window RMS -- a far better loudness proxy for one-shots
    than whole-file RMS, which punishes anything with a long tail."""
    w = int(win * SR)
    if len(x) <= w:
        return math.sqrt(sum(s * s for s in x) / max(1, len(x)))
    acc = sum(s * s for s in x[:w])
    best = acc
    for i in range(w, len(x)):
        acc += x[i] * x[i] - x[i - w] * x[i - w]
        if acc > best:
            best = acc
    return math.sqrt(best / w)


def trim_tail(x, floor=0.0012, keep=0.04):
    """Drop trailing samples below ~-58 dBFS. Reverb tails are long and the
    last stretch of them is inaudible but still costs bytes."""
    i = len(x) - 1
    while i > 0 and abs(x[i]) < floor:
        i -= 1
    return x[:min(len(x), i + 1 + int(keep * SR))]


def finalize(x, target_rms, peak_cap):
    """Match perceived loudness, then limit. Returns the delivery buffer."""
    x = dc_block(list(x))
    cur = short_rms(x)
    if cur > 1e-9:
        x = gain(x, target_rms / cur)
    x = soft_clip(x, peak_cap)
    # Saturation pulls RMS down a little; one correction pass lands it close.
    cur = short_rms(x)
    if cur > 1e-9:
        x = soft_clip(gain(x, min(1.6, target_rms / cur)), peak_cap)
    return fade_edges(trim_tail(x))


# ---------------------------------------------------------------------------
# Shared sound layers -- these give the whole game one voice
# ---------------------------------------------------------------------------

def layer_click(bright=6000.0, decay=420.0, dur=0.02):
    """The transient. Short burst of highpassed noise; every physical sound in
    the game starts with one of these."""
    return envelope(highpass(white_noise(dur), bright), punch(0.0004, decay))


def layer_tick(freq, dur=0.03, decay=260.0):
    """Pitched transient ping -- adds 'material' to a click (ice, plastic)."""
    return render_tone(dur, lambda t: freq, osc_sine, punch(0.0003, decay))


def layer_sub(f0, f1, dur, rate=14.0):
    """Sub-bass drop: the weight layer. Sine sweeping f0 -> f1."""
    k = math.log(max(1e-3, f1 / f0)) if f0 > 0 else 0.0
    return render_tone(dur, lambda t: f0 * math.exp(k * min(1.0, t / dur)),
                       osc_sine, punch(0.002, rate))


def layer_snow(dur, open_hz=2600.0, close_hz=380.0, decay=13.0, q=1.1):
    """Compacting snow: pink noise through a fast-closing resonant lowpass."""
    n = pink_noise(dur)
    swept = svf(n, lambda t: close_hz + (open_hz - close_hz) * math.exp(-9.0 * t), q)
    return envelope(swept, punch(0.001, decay))


def layer_ice(dur, freqs, decay=11.0):
    """Ice ring: noise through tuned combs -> crystalline, not just bright."""
    base = envelope(highpass(white_noise(dur * 0.4), 1800.0), punch(0.0006, 55.0))
    out = [0.0] * int(dur * SR)
    for i, f in enumerate(freqs):
        c = comb(base, f, 0.86 - 0.04 * i, 0.28, dur * 0.6)
        c = envelope(c, exp_decay(decay + 2.0 * i))
        overlay(out, c, 0.0, 0.7 / len(freqs))
    return out


def layer_whoosh(dur, f_lo=350.0, f_hi=4200.0, q=2.4, shape=1.0):
    """Doppler-ish pass-by: resonant bandpass rising then falling."""
    n = pink_noise(dur)

    def cut(t):
        u = min(1.0, t / dur)
        arc = math.sin(math.pi * u) ** shape
        return f_lo + (f_hi - f_lo) * arc
    swept = svf(n, cut, q, "bp")
    return envelope(swept, lambda t: math.sin(math.pi * min(1.0, t / dur)) ** 0.7)


def voice_chirp(dur, f0, f1, formants=(880.0, 2350.0), breath=0.25):
    """Penguin voice: pulse-wave larynx through two formant bandpasses.
    Formants are why this reads as a creature and not as a sine sweep."""
    src = render_tone(dur, lambda t: f0 + (f1 - f0) * math.sin(math.pi * min(1.0, t / dur)),
                      osc_pulse(0.32), lambda t: adsr(t, dur, 0.006, dur * 0.3, 0.75, dur * 0.35))
    out = gain(svf(src, formants[0], 5.0, "bp"), 1.0)
    out = mix(out, gain(svf(src, formants[1], 6.0, "bp"), 0.55))
    if breath > 0.0:
        b = envelope(bandpass(white_noise(dur), 2200.0, 6000.0),
                     lambda t: breath * adsr(t, dur, 0.01, dur * 0.5, 0.3, dur * 0.3))
        out = mix(out, b)
    return out


# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------

def sfx_ui_hover():
    """Tiny ice tick. Deliberately the quietest thing in the game."""
    out = [0.0]
    overlay(out, layer_tick(2093.0, 0.035, 190.0), 0.0, 0.9)
    overlay(out, layer_tick(3136.0, 0.025, 300.0), 0.0, 0.35)
    overlay(out, gain(layer_click(7000.0, 700.0, 0.012), 0.5), 0.0)
    return reverb(out, 0.55, 0.5, 0.10, 0.004, 0.09)


def sfx_ui_select():
    """Two-note confirm: pluck transient + C6->G6 blip + short air."""
    out = [0.0]
    overlay(out, gain(layer_click(5000.0, 520.0, 0.015), 0.55), 0.0)
    for i, f in enumerate((1046.5, 1568.0)):
        body = render_tone(0.14, lambda t, f=f: f * (1.0 + 0.03 * math.exp(-60.0 * t)),
                           osc_triangle, punch(0.0015, 26.0))
        shim = render_tone(0.1, lambda t, f=f: f * 2.0, osc_sine, punch(0.001, 44.0))
        overlay(out, mix(body, gain(shim, 0.22)), i * 0.055, 0.9 - 0.15 * i)
    return reverb(out, 0.6, 0.45, 0.13, 0.006, 0.16)


def sfx_countdown():
    """Arcade pip with weight. Heard three times every single race, so it gets
    a transient, a pitch blip, a sub octave and a room."""
    out = [0.0]
    overlay(out, gain(layer_click(4200.0, 620.0, 0.014), 0.5), 0.0)
    # Body: E5 with a fast downward pitch blip -- reads as a struck object.
    body = render_tone(0.22, lambda t: 659.3 * (1.0 + 0.09 * math.exp(-70.0 * t)),
                       osc_triangle, punch(0.0018, 15.0))
    body = mix(body, gain(render_tone(0.22, lambda t: 659.3 * 2.0, osc_sine,
                                      punch(0.0015, 30.0)), 0.28))
    overlay(out, svf(body, lambda t: 5200.0 * math.exp(-6.0 * t) + 900.0, 1.1), 0.0)
    overlay(out, gain(layer_sub(220.0, 164.8, 0.16, 22.0), 0.5), 0.0)
    return reverb(out, 0.6, 0.4, 0.16, 0.008, 0.2)


def sfx_go():
    """GO! -- crack transient, sub drop, filtered C-major stab, sizzle tail."""
    out = [0.0]
    # Tiny pre-lift so the stab has somewhere to land.
    lift = envelope(svf(pink_noise(0.07), lambda t: 600.0 + 9000.0 * (t / 0.07) ** 2, 2.0, "bp"),
                    lambda t: (t / 0.07) ** 2)
    overlay(out, gain(lift, 0.5), 0.0)
    overlay(out, layer_click(3000.0, 300.0, 0.03), 0.06, 0.9)
    overlay(out, gain(layer_sub(150.0, 55.0, 0.45, 9.0), 1.15), 0.06)
    stab = [0.0]
    for f in (261.63, 329.63, 392.0, 523.25):  # C4 E4 G4 C5
        v = render_tone(0.42, lambda t, f=f: f * (1.0 + 0.006 * math.exp(-40.0 * t)),
                        osc_saw, lambda t: adsr(t, 0.42, 0.004, 0.18, 0.45, 0.2))
        overlay(stab, v, 0.0, 0.42)
    stab = svf(stab, lambda t: 7000.0 * math.exp(-7.0 * t) + 700.0, 1.8)
    overlay(out, stab, 0.06, 0.95)
    sizzle = envelope(highpass(white_noise(0.5), 5200.0), punch(0.001, 11.0))
    overlay(out, sizzle, 0.06, 0.42)
    return reverb(out, 0.74, 0.35, 0.2, 0.01, 0.4)


def sfx_jump():
    """Penguin hop: snow push-off + rising body + a little flipper flap."""
    out = [0.0]
    overlay(out, gain(layer_click(2600.0, 640.0, 0.016), 0.65), 0.0)
    # Push-off against snow: short burst that opens as the feet leave.
    push = envelope(svf(pink_noise(0.1), lambda t: 500.0 + 5200.0 * (t / 0.1), 1.5, "bp"),
                    punch(0.001, 26.0))
    overlay(out, push, 0.0, 0.85)
    body = render_tone(0.24, lambda t: 300.0 + 640.0 * (min(1.0, t / 0.18)) ** 0.55,
                       osc_triangle, lambda t: adsr(t, 0.24, 0.003, 0.12, 0.32, 0.09))
    boing = render_tone(0.24, lambda t: 600.0 + 1280.0 * (min(1.0, t / 0.18)) ** 0.55,
                        osc_sine, lambda t: 0.3 * adsr(t, 0.24, 0.003, 0.1, 0.22, 0.08))
    overlay(out, svf(mix(body, boing), lambda t: 1400.0 + 4200.0 * t, 1.3), 0.004)
    flap = envelope(bandpass(pink_noise(0.14), 700.0, 3200.0),
                    lambda t: 0.35 * math.sin(math.pi * min(1.0, t / 0.14)))
    overlay(out, flap, 0.06)
    return reverb(out, 0.55, 0.5, 0.12, 0.006, 0.2)


def sfx_land():
    """Belly/feet into snow: crunch transient, sub thump, compacting snow."""
    out = [0.0]
    overlay(out, gain(layer_click(1800.0, 380.0, 0.03), 0.8), 0.0)
    overlay(out, gain(layer_sub(115.0, 44.0, 0.3, 15.0), 1.2), 0.0)
    overlay(out, gain(layer_snow(0.3, 3000.0, 320.0, 15.0, 1.3), 0.95), 0.0)
    # The squeak of snow compressing under weight.
    squeak = render_tone(0.12, lambda t: 430.0 - 180.0 * (t / 0.12), osc_triangle,
                         lambda t: 0.16 * adsr(t, 0.12, 0.004, 0.06, 0.2, 0.05))
    overlay(out, squeak, 0.012)
    return reverb(out, 0.6, 0.5, 0.14, 0.008, 0.25)


def sfx_slide():
    """Belly slide start: snow contact then a sustained moving scrape.

    Triggered as a one-shot when the slide state begins, so it has a real
    onset and a settled body rather than being a flat noise loop.
    """
    dur = 1.0
    n = pink_noise(dur)
    # Two LFOs at integer cycles/second-ish rates keep the motion organic
    # without ever sounding like a single warbling sine.
    def cut(t):
        return (1250.0
                + 520.0 * math.sin(TWO_PI * 1.0 * t)
                + 260.0 * math.sin(TWO_PI * 2.0 * t + 1.1)
                + 900.0 * math.exp(-14.0 * t))
    scrape = svf(n, cut, 1.35, "bp")
    scrape = envelope(scrape, lambda t: (0.55 + 0.45 * math.sin(TWO_PI * 3.0 * t + 0.4) ** 2)
                      * min(1.0, t / 0.012) * (1.0 - 0.35 * (t / dur) ** 2))
    # Contact rumble: the board-on-snow weight.
    rumble = envelope(svf(pink_noise(dur), lambda t: 210.0 + 60.0 * math.sin(TWO_PI * 1.0 * t),
                          1.2), lambda t: 0.9 * min(1.0, t / 0.02) * math.exp(-1.1 * t))
    out = mix(scrape, gain(rumble, 0.55))
    overlay(out, gain(layer_snow(0.18, 4200.0, 900.0, 26.0, 1.0), 0.7), 0.0)
    return out


def sfx_swim():
    """Flipper strokes underwater: bubbles + resonant water swish."""
    out = [0.0]
    # Flipper entry tick so the first stroke has an onset under water.
    overlay(out, gain(lowpass(layer_click(1200.0, 500.0, 0.02), 2600.0), 0.55), 0.0)
    for k in range(3):
        t0 = k * 0.12
        f0 = 300.0 + 80.0 * k + rng.uniform(-25.0, 25.0)
        blip = render_tone(0.1, lambda t, f0=f0: f0 * (1.0 + 3.2 * t), osc_sine,
                           punch(0.002, 24.0))
        overlay(out, gain(svf(blip, lambda t: 1600.0, 3.0), 1.0), t0, 0.8)
        stroke = envelope(svf(pink_noise(0.2), lambda t: 420.0 + 1900.0 * math.sin(math.pi * t / 0.2),
                              2.2, "bp"), lambda t: math.sin(math.pi * min(1.0, t / 0.2)) ** 0.8)
        overlay(out, stroke, t0, 0.85)
    # Muffled body: water eats the top end.
    return lowpass(out, 3200.0)


def sfx_splash():
    """Entering water: impact, collapsing cavity, spray, droplets."""
    out = [0.0]
    overlay(out, gain(layer_click(2200.0, 260.0, 0.03), 0.7), 0.0)
    body = svf(white_noise(0.4), lambda t: 4200.0 * math.exp(-7.0 * t) + 260.0, 1.5)
    overlay(out, envelope(body, punch(0.002, 8.0)), 0.0, 1.1)
    # Cavity collapse: the pitch that makes water read as water.
    cav = render_tone(0.3, lambda t: 520.0 * math.exp(-2.4 * t) + 90.0, osc_sine,
                      lambda t: 0.5 * adsr(t, 0.3, 0.006, 0.16, 0.15, 0.1))
    overlay(out, cav, 0.008)
    spray = envelope(highpass(pink_noise(0.45), 3800.0), punch(0.004, 8.5))
    overlay(out, spray, 0.02, 0.55)
    for _ in range(7):
        f0 = rng.uniform(850.0, 2300.0)
        d = render_tone(0.05, lambda t, f0=f0: f0 * (1.0 + 1.8 * t), osc_sine,
                        punch(0.0015, 60.0))
        overlay(out, d, rng.uniform(0.12, 0.42), 0.3)
    return reverb(out, 0.66, 0.45, 0.16, 0.008, 0.3)


def sfx_fish():
    """Fish pickup: wet blip + bright two-note bell + sparkle."""
    out = [0.0]
    blip = render_tone(0.05, lambda t: 700.0 * (1.0 + 2.6 * t), osc_sine, punch(0.001, 55.0))
    overlay(out, gain(svf(blip, 1900.0, 3.0), 0.6), 0.0)
    for i, f in enumerate((1318.5, 1975.5)):  # E6 -> B6
        tracks = []
        for ratio, amp, dec in ((1.0, 1.0, 9.0), (2.76, 0.32, 15.0), (5.4, 0.11, 22.0)):
            tracks.append(render_tone(0.24, lambda t, r=ratio: f * r, osc_sine,
                                      lambda t, a=amp, d=dec: a * math.exp(-d * t)))
        bell = mix(*tracks)
        overlay(out, mix(bell, gain(layer_click(9000.0, 900.0, 0.01), 0.25)),
                i * 0.075, 0.85 - 0.2 * i)
    spark = envelope(highpass(white_noise(0.3), 8000.0), punch(0.004, 14.0))
    overlay(out, spark, 0.02, 0.28)
    return reverb(echo(out, 0.075, 0.22, 2), 0.7, 0.35, 0.18, 0.008, 0.3)


def sfx_powerup():
    """Item box: the box cracks open, then the reward arpeggio rises."""
    out = [0.0]
    overlay(out, gain(layer_click(2500.0, 340.0, 0.03), 0.85), 0.0)
    overlay(out, gain(layer_ice(0.3, (1450.0, 2100.0, 3050.0), 14.0), 0.75), 0.0)
    overlay(out, gain(layer_sub(180.0, 70.0, 0.22, 20.0), 0.55), 0.0)
    notes = (523.25, 659.26, 783.99, 1046.5, 1318.5)  # C E G C E
    arp = [0.0]
    for i, f in enumerate(notes):
        n = render_tone(0.26, lambda t, f=f: f * (1.0 + 0.0025 * math.sin(TWO_PI * 7.0 * t)),
                        osc_pulse(0.42), lambda t: adsr(t, 0.26, 0.003, 0.14, 0.25, 0.09))
        n = svf(n, lambda t, i=i: 1500.0 + 700.0 * i + 5000.0 * math.exp(-9.0 * t), 1.7)
        overlay(arp, mix(n, gain(layer_tick(f * 2.0, 0.02, 320.0), 0.2)), 0.06 + i * 0.07, 0.62)
    overlay(out, arp, 0.0)
    return reverb(echo(out, 0.09, 0.24, 2), 0.72, 0.35, 0.18, 0.01, 0.35)


def sfx_powerup_use():
    """Activation: energy suck-in, zap, then a departing whoosh."""
    out = [0.0]
    suck = envelope(svf(pink_noise(0.14), lambda t: 4000.0 - 3200.0 * (t / 0.14), 2.6, "bp"),
                    lambda t: (t / 0.14) ** 1.4)
    overlay(out, gain(suck, 0.7), 0.0)
    overlay(out, gain(layer_click(3200.0, 400.0, 0.025), 0.9), 0.13)
    zap = render_tone(0.3, lambda t: 1500.0 * math.exp(-9.0 * t) + 150.0, osc_pulse(0.28),
                      punch(0.0015, 11.0))
    overlay(out, gain(svf(zap, lambda t: 4200.0 * math.exp(-5.0 * t) + 500.0, 2.2), 0.55), 0.13)
    overlay(out, gain(layer_sub(210.0, 62.0, 0.3, 12.0), 0.85), 0.13)
    fly = envelope(svf(pink_noise(0.32), lambda t: 700.0 + 6000.0 * (t / 0.32) ** 1.8, 2.0, "bp"),
                   lambda t: adsr(t, 0.32, 0.03, 0.14, 0.5, 0.14))
    overlay(out, fly, 0.14, 0.85)
    return reverb(out, 0.66, 0.4, 0.15, 0.008, 0.3)


def sfx_throw():
    """Snowball release: arm effort + tight doppler whoosh + air tail."""
    out = [0.0]
    overlay(out, gain(layer_click(2000.0, 700.0, 0.014), 0.5), 0.0)
    overlay(out, gain(layer_whoosh(0.3, 380.0, 4000.0, 2.6, 1.2), 1.15), 0.0)
    # Pitched core so the whoosh has direction and isn't just hiss.
    core = render_tone(0.26, lambda t: 240.0 + 820.0 * (t / 0.26) ** 1.6, osc_triangle,
                       lambda t: 0.42 * math.sin(math.pi * min(1.0, t / 0.26)))
    overlay(out, svf(core, lambda t: 2400.0, 1.2), 0.01)
    tail = envelope(highpass(pink_noise(0.24), 4000.0), punch(0.02, 13.0))
    overlay(out, tail, 0.1, 0.28)
    return reverb(out, 0.6, 0.45, 0.12, 0.006, 0.22)


def sfx_snowball_hit():
    """Splat: crack, sub thud, wet snow poof, scattering grains."""
    out = [0.0]
    overlay(out, gain(layer_click(1600.0, 300.0, 0.03), 0.9), 0.0)
    overlay(out, gain(layer_sub(150.0, 52.0, 0.26, 18.0), 1.1), 0.0)
    overlay(out, gain(layer_snow(0.32, 3400.0, 260.0, 13.0, 1.4), 1.0), 0.0)
    # Wet component: short resonant blob.
    wet = render_tone(0.1, lambda t: 300.0 * math.exp(-6.0 * t) + 110.0, osc_sine,
                      punch(0.002, 26.0))
    overlay(out, gain(wet, 0.4), 0.004)
    for _ in range(6):
        g = envelope(highpass(white_noise(0.04), 5000.0), punch(0.001, 90.0))
        overlay(out, g, rng.uniform(0.03, 0.22), 0.18)
    return reverb(out, 0.6, 0.45, 0.14, 0.006, 0.28)


def sfx_shield_break():
    """Ice shatter: impact crack, tuned shards, falling tinkles."""
    out = [0.0]
    overlay(out, gain(layer_click(2400.0, 260.0, 0.035), 1.0), 0.0)
    overlay(out, gain(layer_ice(0.42, (980.0, 1570.0, 2340.0, 3710.0), 9.0), 1.0), 0.0)
    for i, (lo, hi) in enumerate(((2400.0, 5200.0), (3600.0, 7800.0), (5000.0, 9500.0))):
        shard = envelope(bandpass(white_noise(0.26), lo, hi), punch(0.0008, 16.0 + 4.0 * i))
        overlay(out, shard, 0.02 + i * 0.045, 0.55)
    for _ in range(7):
        f0 = rng.uniform(2400.0, 7000.0)
        ting = render_tone(0.12, lambda t, f0=f0: f0, osc_sine, punch(0.0008, 34.0))
        overlay(out, ting, rng.uniform(0.02, 0.3), 0.22)
    overlay(out, gain(layer_sub(120.0, 48.0, 0.2, 20.0), 0.5), 0.0)
    return reverb(out, 0.78, 0.28, 0.22, 0.008, 0.4)


def sfx_shove():
    """Flipper check: body thud + padded whack + feather rustle."""
    out = [0.0]
    overlay(out, gain(layer_click(1400.0, 420.0, 0.022), 0.75), 0.0)
    overlay(out, gain(layer_sub(190.0, 68.0, 0.26, 17.0), 1.0), 0.0)
    boing = render_tone(0.3, lambda t: (250.0 - 110.0 * (t / 0.3)) *
                        (1.0 + 0.16 * math.sin(TWO_PI * 20.0 * t) * math.exp(-6.0 * t)),
                        osc_triangle, punch(0.002, 11.0))
    overlay(out, gain(svf(boing, lambda t: 2200.0 * math.exp(-8.0 * t) + 420.0, 1.6), 0.8), 0.0)
    rustle = envelope(bandpass(pink_noise(0.2), 900.0, 4200.0), punch(0.003, 17.0))
    overlay(out, rustle, 0.006, 0.5)
    return reverb(out, 0.58, 0.5, 0.13, 0.006, 0.24)


def sfx_stumble():
    """Trip: scuff, wobbling descending honk, flustered flipper flap."""
    out = [0.0]
    scuff = envelope(svf(pink_noise(0.16), lambda t: 2600.0 * math.exp(-8.0 * t) + 400.0,
                         1.4, "bp"), punch(0.002, 15.0))
    overlay(out, gain(scuff, 0.9), 0.0)
    wob = render_tone(0.44, lambda t: (430.0 - 250.0 * (t / 0.44)) *
                      (1.0 + 0.11 * math.sin(TWO_PI * 10.0 * t)),
                      osc_triangle, lambda t: adsr(t, 0.44, 0.005, 0.26, 0.3, 0.14))
    overlay(out, gain(svf(wob, lambda t: 3000.0 * math.exp(-3.5 * t) + 500.0, 1.5), 0.95), 0.01)
    overlay(out, gain(layer_sub(150.0, 60.0, 0.2, 19.0), 0.4), 0.0)
    for k in range(2):
        flap = envelope(bandpass(pink_noise(0.1), 600.0, 3000.0),
                        lambda t: 0.4 * math.sin(math.pi * min(1.0, t / 0.1)))
        overlay(out, flap, 0.14 + k * 0.13, 0.5)
    return reverb(out, 0.6, 0.45, 0.13, 0.008, 0.26)


def sfx_checkpoint():
    """Crystal chime. Also used pitched up for icicle warnings, so the
    partials stay inharmonic-but-clean at 1.6x."""
    out = [0.0]
    f = 1567.98  # G6
    tracks = []
    for ratio, amp, dec in ((1.0, 1.0, 4.2), (2.76, 0.38, 7.5), (5.40, 0.14, 11.0),
                            (0.5, 0.30, 3.4)):
        tracks.append(render_tone(0.8, lambda t, r=ratio: f * r, osc_sine,
                                  lambda t, a=amp, d=dec: a * math.exp(-d * t)))
    bell = mix(*tracks)
    overlay(out, envelope(bell, lambda t: adsr(t, 0.8, 0.0015, 0.55, 0.18, 0.22)), 0.0)
    overlay(out, gain(layer_click(9000.0, 800.0, 0.012), 0.3), 0.0)
    shimmer = envelope(highpass(white_noise(0.5), 7500.0), punch(0.003, 10.0))
    overlay(out, shimmer, 0.0, 0.2)
    return reverb(out, 0.8, 0.3, 0.26, 0.012, 0.45)


def sfx_finish():
    """Crossing the line: impact + rising chord + cymbal sizzle."""
    out = [0.0]
    overlay(out, gain(layer_click(2600.0, 280.0, 0.035), 0.85), 0.0)
    overlay(out, gain(layer_sub(160.0, 52.0, 0.5, 8.0), 1.1), 0.0)
    for f in (261.63, 329.63, 392.0, 523.25, 659.26):
        v = render_tone(0.6, lambda t, f=f: f * (1.0 + 0.004 * math.sin(TWO_PI * 5.5 * t)),
                        osc_saw, lambda t: adsr(t, 0.6, 0.008, 0.3, 0.42, 0.26))
        overlay(out, svf(v, lambda t: 6500.0 * math.exp(-4.5 * t) + 900.0, 1.5), 0.0, 0.38)
    crash = envelope(highpass(white_noise(0.7), 4200.0), punch(0.002, 7.0))
    overlay(out, crash, 0.0, 0.4)
    return reverb(out, 0.8, 0.3, 0.24, 0.01, 0.5)


def sfx_victory():
    """Short original fanfare with a bass line under it, then a held chord."""
    out = [0.0]
    seq = ((523.25, 0.0, 0.16), (392.0, 0.16, 0.16), (523.25, 0.32, 0.16),
           (659.26, 0.48, 0.22), (783.99, 0.74, 0.5))
    for f, t0, d in seq:
        lead = render_tone(d + 0.12, lambda t, f=f: f * (1.0 + 0.004 * math.sin(TWO_PI * 5.0 * t)),
                           osc_saw, lambda t, d=d: adsr(t, d + 0.12, 0.008, d * 0.4, 0.6, 0.11))
        lead = svf(lead, lambda t: 5200.0 * math.exp(-3.0 * t) + 1100.0, 1.6)
        overlay(out, lead, t0, 0.6)
        octv = render_tone(d + 0.12, lambda t, f=f: f * 2.0, osc_sine,
                           lambda t, d=d: 0.22 * adsr(t, d + 0.12, 0.008, d * 0.4, 0.5, 0.11))
        overlay(out, octv, t0, 0.6)
        overlay(out, gain(layer_click(3000.0, 700.0, 0.014), 0.22), t0)
        bass = mix(render_tone(d, lambda t, f=f: f / 4.0, osc_saw, punch(0.003, 9.0)),
                   render_tone(d, lambda t, f=f: f / 8.0, osc_sine, punch(0.003, 7.0)))
        overlay(out, lowpass(bass, 1400.0), t0, 0.45)
    # Landing chord.
    for f in (261.63, 329.63, 392.0, 523.25, 784.0):
        chord = render_tone(0.85, lambda t, f=f: f, osc_saw,
                            lambda t: adsr(t, 0.85, 0.01, 0.45, 0.4, 0.34))
        overlay(out, svf(chord, lambda t: 5600.0 * math.exp(-3.0 * t) + 1000.0, 1.5), 1.1, 0.36)
    overlay(out, gain(layer_sub(180.0, 65.0, 0.6, 7.0), 0.9), 1.1)
    overlay(out, gain(layer_ice(0.6, (2093.0, 2637.0, 3136.0), 6.0), 0.5), 1.1)
    crash = envelope(highpass(white_noise(0.8), 4000.0), punch(0.002, 6.0))
    overlay(out, crash, 1.1, 0.34)
    return reverb(out, 0.82, 0.3, 0.22, 0.012, 0.45)


def sfx_unlock():
    """Reward reveal: riser into a bright bell cluster."""
    out = [0.0]
    riser = envelope(svf(pink_noise(0.3), lambda t: 600.0 + 5200.0 * (t / 0.3) ** 2, 2.4, "bp"),
                     lambda t: (t / 0.3) ** 1.6)
    overlay(out, gain(riser, 0.6), 0.0)
    notes = (1046.5, 1318.5, 1568.0, 2093.0)  # C6 E6 G6 C7
    for i, f in enumerate(notes):
        tracks = []
        for ratio, amp, dec in ((1.0, 1.0, 5.0), (2.76, 0.3, 9.0), (5.4, 0.1, 14.0)):
            tracks.append(render_tone(0.34, lambda t, r=ratio: f * r, osc_sine,
                                      lambda t, a=amp, d=dec: a * math.exp(-d * t)))
        overlay(out, mix(*tracks), 0.26 + i * 0.085, 0.6)
    sparkle = envelope(highpass(white_noise(0.55), 7000.0), punch(0.02, 7.0))
    overlay(out, sparkle, 0.26, 0.22)
    overlay(out, gain(layer_sub(150.0, 65.0, 0.4, 9.0), 0.4), 0.26)
    return reverb(echo(out, 0.1, 0.24, 2), 0.82, 0.3, 0.24, 0.012, 0.45)


def sfx_boost():
    """Boost pad / speed burst: whoomph, thrust noise opening up, flutter."""
    dur = 0.7
    out = [0.0]
    overlay(out, gain(layer_click(1800.0, 240.0, 0.04), 0.8), 0.0)
    overlay(out, gain(layer_sub(90.0, 190.0, 0.4, 5.0), 1.0), 0.0)
    thrust = svf(pink_noise(dur), lambda t: 380.0 + 6200.0 * (t / dur) ** 1.35, 2.2, "bp")
    thrust = envelope(thrust, lambda t: adsr(t, dur, 0.02, 0.22, 0.68, 0.24)
                      * (1.0 + 0.12 * math.sin(TWO_PI * 34.0 * t)))
    overlay(out, gain(thrust, 1.25), 0.0)
    rise = render_tone(dur, lambda t: 170.0 + 780.0 * (t / dur) ** 1.35, osc_saw,
                       lambda t: 0.3 * adsr(t, dur, 0.03, 0.25, 0.55, 0.24))
    overlay(out, svf(rise, lambda t: 1200.0 + 5000.0 * (t / dur), 1.4), 0.0)
    return reverb(out, 0.68, 0.4, 0.16, 0.008, 0.32)


def sfx_respawn():
    """Reassemble: reversed-feeling swell into a warm bell resolve."""
    out = [0.0]
    swell = envelope(svf(pink_noise(0.34), lambda t: 400.0 + 4200.0 * (t / 0.34) ** 2, 2.6, "bp"),
                     lambda t: (t / 0.34) ** 2)
    overlay(out, gain(swell, 0.55), 0.0)
    for i in range(5):
        f0 = 523.25 * (1.26 ** i)
        n = render_tone(0.3, lambda t, f0=f0: f0 * (1.0 + 0.22 * t), osc_sine,
                        lambda t: adsr(t, 0.3, 0.02, 0.16, 0.2, 0.1))
        overlay(out, n, 0.06 + i * 0.05, 0.36)
    for f in (523.25, 659.26, 783.99):
        tracks = []
        for ratio, amp, dec in ((1.0, 1.0, 4.0), (2.76, 0.25, 8.0)):
            tracks.append(render_tone(0.45, lambda t, r=ratio: f * r, osc_sine,
                                      lambda t, a=amp, d=dec: a * math.exp(-d * t)))
        overlay(out, mix(*tracks), 0.34, 0.4)
    overlay(out, gain(layer_sub(130.0, 65.0, 0.35, 10.0), 0.35), 0.34)
    return reverb(out, 0.8, 0.32, 0.24, 0.012, 0.4)


def sfx_impact():
    """Generic collision -- lighter sibling of land, same material family."""
    out = [0.0]
    overlay(out, gain(layer_click(2000.0, 460.0, 0.024), 0.8), 0.0)
    overlay(out, gain(layer_sub(130.0, 46.0, 0.24, 17.0), 1.15), 0.0)
    overlay(out, gain(layer_snow(0.26, 2600.0, 300.0, 17.0, 1.2), 0.85), 0.0)
    knock = render_tone(0.1, lambda t: 330.0 * math.exp(-9.0 * t) + 120.0, osc_triangle,
                        punch(0.001, 30.0))
    overlay(out, gain(knock, 0.35), 0.0)
    return reverb(out, 0.58, 0.5, 0.13, 0.006, 0.22)


def sfx_chirp():
    """Penguin call: three formant-filtered chirps that fall in pitch and
    darken across the series, the way a real call series runs out of breath."""
    out = [0.0]
    t0 = 0.0
    for k in range(3):
        drop = 0.82 ** k
        d = rng.uniform(0.08, 0.11) * (1.0 + 0.15 * k)
        f0 = rng.uniform(540.0, 610.0) * drop
        f1 = f0 * rng.uniform(1.5, 1.85) * (1.0 - 0.12 * k)
        c = voice_chirp(d, f0, f1,
                        (rng.uniform(850.0, 980.0) * drop,
                         rng.uniform(2250.0, 2600.0) * drop), 0.24 - 0.07 * k)
        overlay(out, c, t0, 0.95 - 0.18 * k)
        t0 += d + rng.uniform(0.05, 0.085)
    return reverb(out, 0.62, 0.45, 0.14, 0.008, 0.25)


# name -> (builder, target short-term RMS, peak ceiling)
#
# Targets are calibrated so the gameplay tier averages 0.26 short-term RMS --
# the same average the previous set had -- but with a 3.5 dB spread instead of
# the old 7 dB one, so nothing jumps out.  UI sits ~8 dB under gameplay, and
# AudioManager attenuates it a further 4-8 dB on top.
SFX_BUILDERS = {
    "sfx_ui_hover": (sfx_ui_hover, 0.100, 0.50),
    "sfx_ui_select": (sfx_ui_select, 0.130, 0.62),
    "sfx_countdown": (sfx_countdown, 0.275, 0.84),
    "sfx_go": (sfx_go, 0.290, 0.86),
    "sfx_jump": (sfx_jump, 0.255, 0.80),
    "sfx_land": (sfx_land, 0.275, 0.84),
    "sfx_slide": (sfx_slide, 0.200, 0.66),
    "sfx_swim": (sfx_swim, 0.225, 0.74),
    "sfx_splash": (sfx_splash, 0.260, 0.80),
    "sfx_fish": (sfx_fish, 0.245, 0.76),
    "sfx_powerup": (sfx_powerup, 0.260, 0.80),
    "sfx_powerup_use": (sfx_powerup_use, 0.260, 0.80),
    "sfx_throw": (sfx_throw, 0.230, 0.76),
    "sfx_snowball_hit": (sfx_snowball_hit, 0.290, 0.86),
    "sfx_shield_break": (sfx_shield_break, 0.265, 0.82),
    "sfx_shove": (sfx_shove, 0.290, 0.86),
    "sfx_stumble": (sfx_stumble, 0.245, 0.78),
    "sfx_checkpoint": (sfx_checkpoint, 0.215, 0.74),
    "sfx_finish": (sfx_finish, 0.290, 0.86),
    "sfx_victory": (sfx_victory, 0.275, 0.86),
    "sfx_unlock": (sfx_unlock, 0.240, 0.78),
    "sfx_boost": (sfx_boost, 0.275, 0.82),
    "sfx_respawn": (sfx_respawn, 0.220, 0.74),
    "sfx_impact": (sfx_impact, 0.290, 0.86),
    "sfx_chirp": (sfx_chirp, 0.230, 0.74),
}

# Sounds deliberately built as swells (materialise / reveal gestures).  A hard
# transient would be wrong for these, so they are exempt from the onset check.
SWELL_SFX = {"sfx_respawn", "sfx_unlock"}


# ---------------------------------------------------------------------------
# Music instruments
# ---------------------------------------------------------------------------

def inst_glock(freq, dur=0.7):
    """Struck metal bar: inharmonic partials plus a mallet click."""
    partials = ((1.0, 1.0, 5.0), (2.76, 0.3, 8.0), (5.40, 0.1, 12.0), (8.93, 0.04, 16.0))
    tracks = []
    for ratio, amp, decay in partials:
        tracks.append(render_tone(dur, lambda t, r=ratio: freq * r, osc_sine,
                                  lambda t, a=amp, d=decay: a * math.exp(-d * t)))
    out = mix(*tracks)
    out = mix(out, gain(layer_click(7000.0, 900.0, 0.008), 0.12))
    return envelope(out, lambda t: adsr(t, dur, 0.0015, 0.5, 0.15, 0.15))


def inst_marimba(freq, dur=0.6):
    """Warm wooden bar -- rounder than glock, good for laid-back tracks."""
    partials = ((1.0, 1.0, 7.0), (3.9, 0.28, 14.0), (10.1, 0.06, 22.0))
    tracks = []
    for ratio, amp, decay in partials:
        tracks.append(render_tone(dur, lambda t, r=ratio: freq * r, osc_sine,
                                  lambda t, a=amp, d=decay: a * math.exp(-d * t)))
    out = mix(*tracks)
    out = mix(out, gain(envelope(lowpass(white_noise(0.01), 3000.0), punch(0.0005, 500.0)), 0.18))
    return envelope(out, lambda t: adsr(t, dur, 0.002, 0.4, 0.1, 0.2))


def inst_pluck(freq, dur=0.5, damp=0.4, bright=0.6):
    """Karplus-Strong string. Cheap to compute, expensive-sounding."""
    n = int(dur * SR)
    d = max(2, int(SR / max(30.0, freq)))
    exc = [rng.uniform(-1.0, 1.0) for _ in range(d)]
    # Brightness = how much of the excitation survives the initial lowpass.
    y = 0.0
    a = bright
    for i in range(d):
        y += a * (exc[i] - y)
        exc[i] = y
    buf = list(exc)
    out = [0.0] * n
    prev = 0.0
    for i in range(n):
        v = buf[i % d]
        nxt = (1.0 - 0.0009 * (1.0 + damp * 4.0)) * 0.5 * (v + prev)
        prev = v
        out[i] = v
        buf[i % d] = nxt
    return envelope(out, lambda t: adsr(t, dur, 0.0008, dur * 0.7, 0.35, dur * 0.28))


def inst_bass(freq, dur=0.4, drive=0.6):
    """Sub sine + resonant saw pluck. The sub is the low end the old mix
    was missing entirely."""
    sub = render_tone(dur, lambda t: freq * (1.0 + 0.35 * math.exp(-45.0 * t)), osc_sine,
                      lambda t: adsr(t, dur, 0.004, dur * 0.7, 0.55, dur * 0.25))
    body = render_tone(dur, lambda t: freq, osc_saw,
                       lambda t: adsr(t, dur, 0.003, dur * 0.5, 0.35, dur * 0.3))
    body = svf(body, lambda t: freq * 4.0 + 1500.0 * math.exp(-12.0 * t), 2.2)
    out = mix(gain(sub, 1.0), gain(body, 0.5))
    return soft_clip(out, 1.0 / max(0.2, drive))


def inst_pad(freqs, dur, cutoff=2000.0, detune=0.006):
    """Detuned saw stack through a slowly opening filter -> analog warmth."""
    tracks = []
    for f in freqs:
        for k, det in enumerate((1.0 - detune, 1.0, 1.0 + detune)):
            tracks.append(render_tone(dur, lambda t, f=f, d=det: f * d, osc_saw,
                                      lambda t: 1.0 / (3.0 * len(freqs))))
    out = mix(*tracks)
    out = svf(out, lambda t: cutoff * (0.55 + 0.45 * math.sin(math.pi * min(1.0, t / dur))), 1.1)
    return envelope(out, lambda t: adsr(t, dur, dur * 0.22, 0.05, 0.85, dur * 0.3))


def inst_lead(freq, dur, width=0.35):
    """Pulse lead with vibrato and a filter that tracks the note."""
    out = render_tone(dur, lambda t: freq * (1.0 + 0.004 * math.sin(TWO_PI * 5.5 * t)),
                      osc_pulse(width), lambda t: adsr(t, dur, 0.004, dur * 0.35, 0.6, dur * 0.3))
    out = svf(out, lambda t: freq * 2.5 + 3600.0 * math.exp(-7.0 * t) + 600.0, 1.9)
    return out


def inst_choir(freq, dur):
    """Breathy sine choir for the dreamy track."""
    tracks = []
    for det, amp in ((0.995, 0.5), (1.0, 1.0), (1.006, 0.5), (2.0, 0.18), (3.0, 0.07)):
        tracks.append(render_tone(dur, lambda t, d=det: freq * d *
                                  (1.0 + 0.003 * math.sin(TWO_PI * 4.5 * t + d)),
                                  osc_sine, lambda t, a=amp: a * 0.4))
    out = mix(*tracks)
    breath = envelope(bandpass(pink_noise(dur), 1200.0, 5000.0), lambda t: 0.05)
    out = mix(out, breath)
    return envelope(out, lambda t: adsr(t, dur, dur * 0.3, 0.1, 0.8, dur * 0.35))


def drum_kick(tune=1.0, punchy=1.0):
    """Click + swept sine + saturated sub. Reads on phone speakers because of
    the click, and on headphones because of the sub."""
    d = 0.28
    body = render_tone(d, lambda t: (155.0 * math.exp(-32.0 * t * punchy) + 46.0) * tune,
                       osc_sine, punch(0.0008, 17.0))
    sub = render_tone(d, lambda t: 48.0 * tune, osc_sine, punch(0.002, 9.0))
    click = envelope(highpass(white_noise(0.012), 1800.0), punch(0.0004, 700.0))
    return soft_clip(mix(body, gain(sub, 0.55), gain(click, 0.35)), 1.1)


def drum_snare(bright=1.0):
    noise = envelope(bandpass(white_noise(0.2), 1200.0, 7000.0 * bright), punch(0.0008, 24.0))
    noise = mix(noise, gain(envelope(highpass(white_noise(0.05), 4000.0),
                                     punch(0.0004, 90.0)), 0.6))
    tone = mix(render_tone(0.12, lambda t: 185.0, osc_triangle, punch(0.001, 30.0)),
               render_tone(0.12, lambda t: 248.0, osc_sine, punch(0.001, 34.0)))
    return soft_clip(mix(noise, gain(tone, 0.55)), 1.1)


def drum_clap():
    """Three offset noise bursts + a body -- the classic handclap trick."""
    out = [0.0]
    for k, t0 in enumerate((0.0, 0.011, 0.023)):
        b = envelope(bandpass(white_noise(0.05), 1100.0, 5200.0), punch(0.0006, 120.0))
        overlay(out, b, t0, 0.8 - 0.15 * k)
    tail = envelope(bandpass(white_noise(0.18), 1000.0, 4200.0), punch(0.02, 22.0))
    overlay(out, tail, 0.023, 0.55)
    return out


def drum_hat(open_amt=0.0):
    """808-style metallic hat: six inharmonic squares, highpassed. Far less
    'shhh' than plain noise."""
    d = 0.045 + open_amt * 0.18
    ratios = (2.0, 3.0, 4.16, 5.43, 6.79, 8.21)
    base = 320.0
    tracks = []
    for r in ratios:
        tracks.append(render_tone(d, lambda t, r=r: base * r, osc_square,
                                  lambda t: 1.0 / len(ratios)))
    metal = highpass(mix(*tracks), 7000.0)
    metal = mix(metal, gain(highpass(white_noise(d), 8000.0), 0.35))
    return envelope(metal, punch(0.0004, 75.0 - open_amt * 62.0))


def drum_shaker():
    return envelope(highpass(pink_noise(0.08), 4200.0),
                    lambda t: math.sin(math.pi * min(1.0, t / 0.055)) ** 2 * math.exp(-14.0 * t))


def drum_tom(freq):
    body = render_tone(0.3, lambda t: freq * (1.0 + 0.5 * math.exp(-22.0 * t)), osc_sine,
                       punch(0.001, 12.0))
    skin = envelope(bandpass(white_noise(0.09), 300.0, 2600.0), punch(0.0006, 45.0))
    return mix(body, gain(skin, 0.3))


def drum_ride():
    """Soft ping for the relaxed track."""
    ratios = (1.0, 2.34, 3.71, 5.12)
    tracks = []
    for r in ratios:
        tracks.append(render_tone(0.4, lambda t, r=r: 1050.0 * r, osc_sine,
                                  lambda t: 1.0 / len(ratios)))
    ping = envelope(mix(*tracks), punch(0.001, 11.0))
    wash = envelope(highpass(white_noise(0.4), 6500.0), punch(0.002, 9.0))
    return mix(ping, gain(wash, 0.5))


# ---------------------------------------------------------------------------
# Music sequencing (wrap-add keeps loops seamless: tails spill onto the start)
# ---------------------------------------------------------------------------

# C major pentatonic across three octaves -- the arctic-cheerful palette that
# ties every melodic SFX and every track together.
PENTA = [48, 50, 52, 55, 57, 60, 62, 64, 67, 69, 72, 74, 76, 79, 81, 84]

CHORD_PAD = {
    "C": [48, 55, 60, 64, 67],
    "F": [53, 60, 65, 69, 72],
    "G": [55, 62, 67, 71, 74],
    "Am": [45, 52, 57, 60, 64],
    "Em": [52, 59, 64, 67, 71],
    "Dm": [50, 57, 62, 65, 69],
}

CHORD_BASS = {"C": 36, "F": 41, "G": 43, "Am": 33, "Em": 40, "Dm": 38}

# Scale-degree offsets that are consonant over each chord (index into PENTA).
CHORD_ANCHOR = {"C": 0, "F": 3, "G": 3, "Am": 4, "Em": 2, "Dm": 1}


def add_wrapped(left, right, start_sample, samples, gain_, pan):
    """Pan 0.0 = hard left, 1.0 = hard right. Wraps around the loop buffer."""
    n = len(left)
    gl = gain_ * math.cos(pan * math.pi / 2.0)
    gr = gain_ * math.sin(pan * math.pi / 2.0)
    start = start_sample % n
    for i, s in enumerate(samples):
        idx = start + i
        if idx >= n:
            idx -= n * (idx // n)
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
            j = i + off
            if j >= n:
                j -= n
            left[j] += a[i] * g
            right[j] += b[i] * g
        g *= feedback


def gen_motif(mel_rng, subdiv, bars_per_phrase=2):
    """Build a rhythmic/melodic motif once, then the phrase generator repeats
    it with variation. Motifs are the difference between 'composed' and
    'random arpeggio'."""
    steps = subdiv * bars_per_phrase
    motif = []
    step = 0
    idx = 0
    while step < steps:
        length = mel_rng.choice((1, 1, 2, 2, 3))
        motif.append((step, idx, length))
        idx += mel_rng.choice((-2, -1, -1, 1, 1, 2, 3))
        idx = max(-3, min(6, idx))
        step += length + mel_rng.choice((0, 0, 1))
    return motif


def gen_phrase(bars, subdiv, prog, mel_rng, octave_shift=0, bars_per_phrase=2):
    """Repeat the motif across the loop, re-anchored to each chord and varied
    on the final repeat so the loop has a sense of question/answer."""
    motif = gen_motif(mel_rng, subdiv, bars_per_phrase)
    events = []
    reps = max(1, bars // bars_per_phrase)
    for r in range(reps):
        bar0 = r * bars_per_phrase
        anchor = CHORD_ANCHOR[prog[bar0 % len(prog)]] + 5
        last = r == reps - 1
        for si, (step, off, length) in enumerate(motif):
            idx = anchor + off
            if last and si >= len(motif) - 2:
                idx += 2  # lift the final gesture
            if r % 2 == 1 and si % 3 == 0:
                idx += 1  # gentle variation on odd repeats
            idx = max(0, min(len(PENTA) - 1, idx))
            events.append((bar0 * subdiv + step, PENTA[idx] + octave_shift, length))
    return events


def render_song(bpm, bars, prog, style):
    beat = 60.0 / bpm
    bar = beat * 4.0
    total = bars * bar
    n = int(round(total * SR))
    left = [0.0] * n
    right = [0.0] * n
    half = max(1, bars // 2)

    mel_rng = random.Random(style["seed"])

    # --- Pads: one chord per bar, doubled and offset for stereo width -------
    pad_cache = {}
    for b in range(bars):
        chord = prog[b % len(prog)]
        if chord not in pad_cache:
            pad_cache[chord] = inst_pad([midi_to_hz(m) for m in CHORD_PAD[chord]],
                                        bar * 1.05, style.get("pad_cutoff", 2000.0))
        pad = pad_cache[chord]
        start = int(b * bar * SR)
        g = style["pad_gain"] * (0.75 if b < half else 1.0)
        add_wrapped(left, right, start, pad, g, 0.28)
        add_wrapped(left, right, start + int(0.013 * SR), pad, g * 0.85, 0.72)

    # --- Choir / texture layer (optional) ----------------------------------
    if style.get("choir_gain", 0.0) > 0.0:
        choir_cache = {}
        for b in range(bars):
            if b % 2:
                continue
            chord = prog[b % len(prog)]
            if chord not in choir_cache:
                freqs = [midi_to_hz(m + 12) for m in CHORD_PAD[chord][1:4]]
                choir_cache[chord] = [inst_choir(f, bar * 2.05) for f in freqs]
            for k, v in enumerate(choir_cache[chord]):
                add_wrapped(left, right, int(b * bar * SR), v,
                            style["choir_gain"], 0.2 + 0.3 * k)

    # --- Bass: sub-anchored root plus pattern ------------------------------
    bass_cache = {}
    for b in range(bars):
        root = CHORD_BASS[prog[b % len(prog)]]
        for pos, interval, length in style["bass_pattern"]:
            m = root + interval
            key = (m, length)
            if key not in bass_cache:
                bass_cache[key] = inst_bass(midi_to_hz(m), beat * length * 0.92,
                                            style.get("bass_drive", 0.6))
            start = int((b * bar + pos * beat) * SR)
            add_wrapped(left, right, start, bass_cache[key], style["bass_gain"], 0.5)
        # Leading tone into the next chord on the last eighth.
        if style.get("bass_walk", False) and b < bars - 1:
            nxt = CHORD_BASS[prog[(b + 1) % len(prog)]]
            step = nxt - 2 if nxt > root else nxt + 2
            key = (step, 0.5)
            if key not in bass_cache:
                bass_cache[key] = inst_bass(midi_to_hz(step), beat * 0.46,
                                            style.get("bass_drive", 0.6))
            add_wrapped(left, right, int((b * bar + 3.5 * beat) * SR), bass_cache[key],
                        style["bass_gain"] * 0.8, 0.5)

    # --- Drums: A/B arrangement, fill on the last bar ----------------------
    kick = drum_kick(style.get("kick_tune", 1.0), style.get("kick_punch", 1.0))
    snare = drum_snare(style.get("snare_bright", 1.0))
    clap = drum_clap()
    shaker = drum_shaker()
    ride = drum_ride()
    hat_c = drum_hat(0.0)
    hat_o = drum_hat(0.6)
    toms = [drum_tom(f) for f in (190.0, 150.0, 118.0)]
    for b in range(bars):
        bar_start = b * bar
        full = b >= half
        last = b == bars - 1
        for pos in style["kick_beats"]:
            add_wrapped(left, right, int((bar_start + pos * beat) * SR), kick,
                        style["drum_gain"], 0.5)
        if full or style.get("snare_always", False):
            for pos in style["snare_beats"]:
                add_wrapped(left, right, int((bar_start + pos * beat) * SR), snare,
                            style["drum_gain"] * 0.72, 0.5)
            if style.get("clap", False):
                for pos in style["snare_beats"]:
                    add_wrapped(left, right, int((bar_start + pos * beat) * SR), clap,
                                style["drum_gain"] * 0.4, 0.44)
        hat_step = style["hat_subdiv"]
        if hat_step > 0.0 and (full or not style.get("hats_second_half_only", False)):
            for k in range(int(4 * hat_step)):
                pos = k / hat_step
                is_open = style["open_hat"] and k % max(1, int(hat_step * 2)) == int(hat_step)
                sample = hat_o if is_open else hat_c
                pan = 0.36 if k % 2 == 0 else 0.64
                g = style["hat_gain"] * (1.0 if k % int(max(1, hat_step)) == 0 else 0.62)
                add_wrapped(left, right, int((bar_start + pos * beat) * SR), sample, g, pan)
        if style.get("shaker", False):
            for k in range(8):
                swing = 0.06 * beat if (k % 2 and style.get("swing", False)) else 0.0
                g = style["hat_gain"] * (0.62 if k % 2 else 0.95)
                add_wrapped(left, right, int((bar_start + k * 0.5 * beat + swing) * SR),
                            shaker, g, 0.6 if k % 2 else 0.4)
        if style.get("ride", False) and full:
            for k in range(4):
                add_wrapped(left, right, int((bar_start + k * beat) * SR), ride,
                            style["hat_gain"] * 0.55, 0.62)
        if last and style.get("fill", True):
            for k in range(4):
                pos = 3.0 + k * 0.25
                add_wrapped(left, right, int((bar_start + pos * beat) * SR),
                            toms[min(2, k // 2)] if k < 3 else snare,
                            style["drum_gain"] * 0.6, 0.35 + 0.1 * k)

    # --- Melody bus (its own reverb + ping-pong echo) ----------------------
    mel_l = [0.0] * n
    mel_r = [0.0] * n
    subdiv = style["mel_subdiv"]
    step_len = bar / subdiv
    voice = style.get("mel_voice", "glock")
    inst_cache = {}
    for step, midi, length in gen_phrase(bars, subdiv, prog, mel_rng, style["mel_octave"],
                                         style.get("phrase_bars", 2)):
        key = (midi, length)
        if key not in inst_cache:
            d = step_len * length + 0.35
            f = midi_to_hz(midi)
            if voice == "glock":
                s = inst_glock(f, d)
            elif voice == "marimba":
                s = inst_marimba(f, d)
            elif voice == "pluck":
                s = inst_pluck(f, d, 0.35, 0.55)
            else:
                s = inst_lead(f, step_len * length * 0.95, style.get("lead_width", 0.35))
            inst_cache[key] = s
        start = int(step * step_len * SR)
        pan = 0.42 + 0.16 * ((step // 2) % 2)
        add_wrapped(mel_l, mel_r, start, inst_cache[key], style["mel_gain"], pan)
    wrapped_echo(mel_l, mel_r, beat * 0.75, style["echo_fb"], 3)

    # --- Counter-melody in the second half ---------------------------------
    if style.get("counter_gain", 0.0) > 0.0:
        c_rng = random.Random(style["seed"] + 77)
        c_cache = {}
        for step, midi, length in gen_phrase(bars, subdiv // 2, prog, c_rng,
                                             style["mel_octave"] - 12, 2):
            if step * 2 < half * subdiv:
                continue
            key = (midi, length)
            if key not in c_cache:
                c_cache[key] = inst_pluck(midi_to_hz(midi), step_len * 2 * length + 0.3,
                                          0.5, 0.45)
            add_wrapped(mel_l, mel_r, int(step * step_len * 2 * SR), c_cache[key],
                        style["counter_gain"], 0.66)

    for i in range(n):
        left[i] += mel_l[i]
        right[i] += mel_r[i]

    # --- Master glue: DC block + gentle saturation -------------------------
    left = soft_clip(dc_block(left), 0.85)
    right = soft_clip(dc_block(right), 0.85)
    return left, right


def music_title():
    """Warm, inviting, unhurried. Plucks + glock over a soft pulse."""
    prog = ["C", "Am", "F", "G", "C", "Am", "Dm", "G", "F", "G"]
    style = {
        "seed": 4201,
        "pad_gain": 0.34,
        "pad_cutoff": 2200.0,
        "bass_gain": 0.34,
        "bass_drive": 0.7,
        "bass_pattern": [(0.0, 0, 1.5), (2.0, 0, 1.0), (3.0, 7, 0.8)],
        "bass_walk": True,
        "drum_gain": 0.34,
        "kick_beats": [0.0, 2.5],
        "snare_beats": [2.0],
        "kick_tune": 0.95,
        "kick_punch": 0.9,
        "hat_subdiv": 1.0,
        "hat_gain": 0.145,
        "open_hat": False,
        "hats_second_half_only": True,
        "shaker": True,
        "swing": True,
        "ride": True,
        "mel_subdiv": 8,
        "mel_voice": "glock",
        "mel_octave": 0,
        "mel_gain": 0.5,
        "counter_gain": 0.26,
        "phrase_bars": 2,
        "echo_fb": 0.3,
    }
    return render_song(100, 10, prog, style)  # 10 bars @ 100 BPM = 24.0s


def music_race():
    """Driving but friendly: four-on-the-floor, offbeat hats, chip lead."""
    prog = ["C", "C", "F", "F", "Am", "Am", "G", "G",
            "C", "C", "Dm", "Dm", "F", "F", "G", "G"]
    style = {
        "seed": 4202,
        "pad_gain": 0.24,
        "pad_cutoff": 2300.0,
        "bass_gain": 0.68,
        "bass_drive": 0.85,
        "bass_pattern": [(0.0, 0, 0.9), (0.75, 0, 0.6), (1.5, 12, 0.45), (2.0, 0, 0.9),
                         (2.75, 0, 0.6), (3.25, 7, 0.6)],
        "bass_walk": True,
        "drum_gain": 0.44,
        "kick_beats": [0.0, 1.0, 2.0, 2.75, 3.0],
        "snare_beats": [1.0, 3.0],
        "snare_always": True,
        "clap": True,
        "hat_subdiv": 2.0,
        "hat_gain": 0.105,
        "open_hat": True,
        "shaker": False,
        "mel_subdiv": 8,
        "mel_voice": "lead",
        "lead_width": 0.3,
        "mel_octave": 0,
        "mel_gain": 0.3,
        "counter_gain": 0.18,
        "phrase_bars": 2,
        "echo_fb": 0.26,
    }
    return render_song(128, 16, prog, style)  # 16 bars @ 128 BPM = 30.0s


def music_final():
    """Final lap: minor, faster, 16th hats, aggressive bass, lead up an octave."""
    prog = ["Am", "Am", "F", "F", "C", "C", "G", "G", "Am", "F", "G", "G"]
    style = {
        "seed": 4203,
        "pad_gain": 0.24,
        "pad_cutoff": 2600.0,
        "bass_gain": 0.66,
        "bass_drive": 1.0,
        "bass_pattern": [(0.0, 0, 0.45), (0.5, 0, 0.45), (1.0, 0, 0.45), (1.5, 7, 0.45),
                         (2.0, 0, 0.45), (2.5, 0, 0.45), (3.0, 12, 0.45), (3.5, 7, 0.45)],
        "drum_gain": 0.48,
        "kick_beats": [0.0, 1.0, 2.0, 3.0],
        "snare_beats": [1.0, 3.0, 3.75],
        "snare_always": True,
        "snare_bright": 1.15,
        "clap": True,
        "kick_tune": 1.05,
        "hat_subdiv": 4.0,
        "hat_gain": 0.075,
        "open_hat": True,
        "shaker": False,
        "mel_subdiv": 16,
        "mel_voice": "lead",
        "lead_width": 0.22,
        "mel_octave": 12,
        "mel_gain": 0.26,
        "counter_gain": 0.16,
        "phrase_bars": 2,
        "echo_fb": 0.22,
    }
    return render_song(132, 12, prog, style)  # 12 bars @ 132 BPM = 21.8s


def music_aurora():
    """Twilight climb: slow, wide, choir + bells with long echoes."""
    prog = ["Am", "Am", "Em", "Em", "F", "F", "C", "G", "Am", "F", "G", "G"]
    style = {
        "seed": 4204,
        "pad_gain": 0.4,
        "pad_cutoff": 1500.0,
        "choir_gain": 0.16,
        "bass_gain": 0.46,
        "bass_drive": 0.6,
        "bass_pattern": [(0.0, 0, 2.0), (2.0, 7, 1.2), (3.0, 0, 0.8)],
        "bass_walk": True,
        "drum_gain": 0.3,
        "kick_beats": [0.0, 2.5],
        "snare_beats": [2.0],
        "kick_tune": 0.9,
        "kick_punch": 0.8,
        "hat_subdiv": 0.0,
        "hat_gain": 0.07,
        "open_hat": False,
        "shaker": True,
        "swing": False,
        "ride": True,
        "mel_subdiv": 8,
        "mel_voice": "glock",
        "mel_octave": 12,
        "mel_gain": 0.38,
        "counter_gain": 0.18,
        "phrase_bars": 2,
        "echo_fb": 0.36,
    }
    return render_song(92, 12, prog, style)  # 12 bars @ 92 BPM = 31.3s


def music_iceberg():
    """Sunset bay: relaxed swung groove, marimba lead, warm bass."""
    prog = ["F", "F", "C", "C", "Dm", "Dm", "G", "G", "F", "G", "C", "C"]
    style = {
        "seed": 4205,
        "pad_gain": 0.28,
        "pad_cutoff": 1900.0,
        "bass_gain": 0.56,
        "bass_drive": 0.7,
        "bass_pattern": [(0.0, 0, 0.8), (1.5, 7, 0.5), (2.0, 0, 0.8), (3.5, 12, 0.4)],
        "bass_walk": True,
        "drum_gain": 0.38,
        "kick_beats": [0.0, 1.75, 2.5],
        "snare_beats": [1.0, 3.0],
        "snare_always": True,
        "kick_tune": 1.0,
        "hat_subdiv": 2.0,
        "hat_gain": 0.068,
        "open_hat": True,
        "hats_second_half_only": True,
        "shaker": True,
        "swing": True,
        "ride": True,
        "mel_subdiv": 8,
        "mel_voice": "marimba",
        "mel_octave": 0,
        "mel_gain": 0.52,
        "counter_gain": 0.24,
        "phrase_bars": 2,
        "echo_fb": 0.3,
    }
    return render_song(112, 12, prog, style)  # 12 bars @ 112 BPM = 25.7s


MUSIC_BUILDERS = {
    "music_title": music_title,
    "music_race": music_race,
    "music_final": music_final,
    "music_aurora": music_aurora,
    "music_iceberg": music_iceberg,
}


# ---------------------------------------------------------------------------
# Measurement (so this file can prove what it claims without ears)
# ---------------------------------------------------------------------------

def _fft(a):
    n = len(a)
    if n == 1:
        return a
    even = _fft(a[0::2])
    odd = _fft(a[1::2])
    out = [0j] * n
    for k in range(n // 2):
        tw = cmath.exp(-2j * math.pi * k / n) * odd[k]
        out[k] = even[k] + tw
        out[k + n // 2] = even[k] - tw
    return out


_FFT_N = 512
_HANN = [0.5 - 0.5 * math.cos(TWO_PI * i / _FFT_N) for i in range(_FFT_N)]


def _spectrum(x, start, stop, max_frames=48):
    acc = [0.0] * (_FFT_N // 2)
    frames = 0
    hop = _FFT_N
    span = max(_FFT_N, stop - start)
    stride = max(hop, span // max_frames)
    i = start
    while i + _FFT_N <= stop and frames < max_frames:
        buf = [complex(x[i + k] * _HANN[k], 0.0) for k in range(_FFT_N)]
        sp = _fft(buf)
        for k in range(_FFT_N // 2):
            acc[k] += abs(sp[k])
        frames += 1
        i += stride
    if frames == 0:
        return None
    return [v / frames for v in acc]


def _bands(sp):
    tot = sum(sp) + 1e-12
    b = [0.0, 0.0, 0.0, 0.0]
    for k, m in enumerate(sp):
        f = k * SR / _FFT_N
        if f < 200.0:
            b[0] += m
        elif f < 800.0:
            b[1] += m
        elif f < 3500.0:
            b[2] += m
        else:
            b[3] += m
    return [v / tot for v in b]


def _centroid(sp):
    num = den = 0.0
    for k, m in enumerate(sp):
        num += (k * SR / _FFT_N) * m
        den += m
    return num / (den + 1e-12)


def measure(name, mono, channels, path):
    n = len(mono)
    peak = max((abs(s) for s in mono), default=0.0)
    rms = math.sqrt(sum(s * s for s in mono) / max(1, n))
    srms = short_rms(mono)
    # Onset sharpness of the *first* event: time to reach 90% of the loudest
    # sample inside the opening 300 ms.  Measuring against the global peak
    # would mis-score anything whose climax is late (a fanfare, a riser).
    head = min(n, int(0.3 * SR))
    p0 = max((abs(s) for s in mono[:head]), default=0.0)
    thr = 0.9 * p0
    atk_ms = 0.0
    for i in range(head):
        if abs(mono[i]) >= thr:
            atk_ms = i / SR * 1000.0
            break
    sp_all = _spectrum(mono, 0, n)
    sp0 = _spectrum(mono, 0, max(_FFT_N, int(n * 0.25)))
    sp1 = _spectrum(mono, int(n * 0.6), n)
    b = _bands(sp_all) if sp_all else [0.0] * 4
    c0 = _centroid(sp0) if sp0 else 0.0
    c1 = _centroid(sp1) if sp1 else 0.0
    MEASURED[name] = dict(ch=channels, dur=n / SR, peak=peak, rms=rms, srms=srms,
                          crest=peak / (rms + 1e-9), atk=atk_ms,
                          lo=b[0], lm=b[1], mid=b[2], hi=b[3],
                          c0=c0, c1=c1, move=(c1 + 1e-9) / (c0 + 1e-9), path=path)


# ---------------------------------------------------------------------------
# WAV / OGG writing
# ---------------------------------------------------------------------------

def _pack_frames(channels):
    frames = bytearray()
    n = len(channels[0])
    for i in range(n):
        for ch in channels:
            v = max(-1.0, min(1.0, ch[i]))
            frames += struct.pack("<h", int(v * 32767))
    return bytes(frames)


def _write_wav(path, channels):
    with wave.open(path, "wb") as w:
        w.setnchannels(len(channels))
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(_pack_frames(channels))


def write_mono(name, samples, target_rms, peak_cap):
    samples = finalize(samples, target_rms, peak_cap)
    path = os.path.join(OUT_DIR, name + ".wav")
    _write_wav(path, [samples])
    measure(name, samples, 1, path)
    m = MEASURED[name]
    print("wrote %-22s %5.2fs  peak %.2f  rms(150ms) %.3f  atk %5.1fms  %6.1f KB"
          % (name + ".wav", m["dur"], m["peak"], m["srms"], m["atk"],
             os.path.getsize(path) / 1024.0))


def _have_ffmpeg():
    return shutil.which("ffmpeg") is not None


def write_music(name, left, right, target_rms=0.115, peak_cap=0.80, quality="4"):
    """Music ships as OGG (the game loads music_*.ogg). The WAV is an
    intermediate and is deleted after encoding so it can never shadow the OGG
    in AudioManager's filename lookup.

    Music is matched by full-length RMS rather than peak so all five tracks
    sit at the same level regardless of how dense their arrangement is.
    """
    n = len(left)
    cur = math.sqrt(sum((a + b) * (a + b) * 0.25 for a, b in zip(left, right)) / max(1, n))
    g = target_rms / max(cur, 1e-9)
    left = soft_clip(gain(left, g), peak_cap)
    right = soft_clip(gain(right, g), peak_cap)
    wav_path = os.path.join(OUT_DIR, name + ".wav")
    ogg_path = os.path.join(OUT_DIR, name + ".ogg")
    _write_wav(wav_path, [left, right])
    mono = [(a + b) * 0.5 for a, b in zip(left, right)]
    if _have_ffmpeg():
        # -bitexact / -map_metadata -1 strip the encoder version string and
        # tags so the payload does not change with the ffmpeg build.  The Ogg
        # *container* still gets a random stream serial from libavformat, so
        # the file bytes differ between runs even though the decoded PCM is
        # identical -- expect a diff on every regenerate.
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-fflags", "+bitexact",
                        "-i", wav_path, "-flags:a", "+bitexact", "-map_metadata", "-1",
                        "-q:a", quality, ogg_path], check=True)
        os.remove(wav_path)
        out_path = ogg_path
    else:
        out_path = wav_path
        print("  !! ffmpeg not found -- left %s.wav in place; the game expects "
              "%s.ogg. Install ffmpeg and re-run." % (name, name))
    measure(name, mono, 2, out_path)
    mm = MEASURED[name]
    print("wrote %-22s %5.2fs  peak %.2f  rms %.3f  lo %.2f  %6.1f KB"
          % (os.path.basename(out_path), mm["dur"], mm["peak"], mm["rms"], mm["lo"],
             os.path.getsize(out_path) / 1024.0))


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def verify_all():
    print("\n--- verification "
          "(atk=transient onset, move=cent_late/cent_early, bands sum to 1) ---")
    print("%-20s %2s %6s %5s %6s %6s %5s %7s | %5s %5s %5s %5s | %5s"
          % ("name", "ch", "dur", "peak", "rms", "s-rms", "crest", "atk_ms",
             "lo", "lomid", "mid", "hi", "move"))
    failures = []
    for name in sorted(MEASURED):
        m = MEASURED[name]
        status = []
        if not os.path.isfile(m["path"]):
            failures.append("%s: missing output file" % name)
            continue
        if m["dur"] < 0.03:
            status.append("TOO SHORT")
        if m["srms"] < 0.02:
            status.append("NEAR SILENT")
        if m["peak"] > 0.90:
            status.append("TOO HOT")
        is_sfx = name.startswith("sfx_")
        if is_sfx and name not in SWELL_SFX and m["atk"] > 200.0:
            status.append("NO TRANSIENT")
        if is_sfx and 0.93 < m["move"] < 1.07 and name not in ("sfx_ui_hover",):
            status.append("STATIC TIMBRE")
        if not is_sfx and m["lo"] < 0.10:
            status.append("NO LOW END")
        if status:
            failures.append("%s: %s" % (name, ", ".join(status)))
        print("%-20s %2d %6.2f %5.2f %6.4f %6.3f %5.1f %7.1f | %5.2f %5.2f %5.2f %5.2f | %5.2f  %s"
              % (name, m["ch"], m["dur"], m["peak"], m["rms"], m["srms"], m["crest"],
                 m["atk"], m["lo"], m["lm"], m["mid"], m["hi"], m["move"],
                 ",".join(status) if status else "ok"))
    sfx = [m for k, m in MEASURED.items() if k.startswith("sfx_")]
    gameplay = [m for k, m in MEASURED.items()
                if k.startswith("sfx_") and not k.startswith("sfx_ui_")]
    ui = [m for k, m in MEASURED.items() if k.startswith("sfx_ui_")]
    total_kb = sum(os.path.getsize(m["path"]) for m in MEASURED.values()) / 1024.0
    print("\nloudness spread (short-term RMS): gameplay %.3f-%.3f, UI %.3f-%.3f "
          "(UI is %.1f dB under)"
          % (min(m["srms"] for m in gameplay), max(m["srms"] for m in gameplay),
             min(m["srms"] for m in ui), max(m["srms"] for m in ui),
             20.0 * math.log10(max(m["srms"] for m in ui) /
                               (sum(m["srms"] for m in gameplay) / len(gameplay)))))
    print("peak spread: %.2f-%.2f   mean transient onset: %.1f ms   total audio %.0f KB"
          % (min(m["peak"] for m in sfx), max(m["peak"] for m in sfx),
             sum(m["atk"] for m in sfx) / len(sfx), total_kb))
    if failures:
        raise SystemExit("FAILED:\n" + "\n".join(failures))
    print("all %d files verified" % len(MEASURED))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("--- sfx --------------------------------------------------------")
    for name, (builder, target_rms, peak_cap) in SFX_BUILDERS.items():
        write_mono(name, builder(), target_rms, peak_cap)
    print("--- music ------------------------------------------------------")
    for name, builder in MUSIC_BUILDERS.items():
        l, r = builder()
        write_music(name, l, r)
    verify_all()


if __name__ == "__main__":
    main()
