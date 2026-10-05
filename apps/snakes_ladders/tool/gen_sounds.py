"""Synthesises the game's sound effects so no third-party audio is needed.

Run from apps/snakes_ladders: python3 tool/gen_sounds.py (needs numpy)
"""
import wave
import numpy as np

SR = 22050
rng = np.random.default_rng(7)


def env(n, attack=0.005, decay=6.0):
    t = np.arange(n) / SR
    a = np.clip(t / attack, 0, 1)
    return a * np.exp(-decay * t)


def tone(freq, dur, decay=6.0, harmonics=(1.0, 0.3, 0.1)):
    n = int(SR * dur)
    t = np.arange(n) / SR
    s = sum(h * np.sin(2 * np.pi * freq * (i + 1) * t) for i, h in enumerate(harmonics))
    return s * env(n, decay=decay)


def place(out, sig, at):
    i = int(at * SR)
    out[i:i + len(sig)] += sig[: len(out) - i]


def save(name, sig):
    sig = sig / max(1e-6, np.max(np.abs(sig))) * 0.85
    data = (sig * 32767).astype(np.int16)
    with wave.open(f"assets/sounds/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def click(dur=0.03, freq=1800):
    n = int(SR * dur)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * freq * t) * 0.6
    return (noise * 0.6 + body) * env(n, attack=0.001, decay=120)


# Dice: a handful of wooden clicks, slowing down as the die settles.
dice = np.zeros(int(SR * 0.6))
at = 0.0
gap = 0.035
for k in range(11):
    place(dice, click(freq=1200 + rng.integers(0, 1200)) * (1 - k * 0.06), at)
    at += gap
    gap *= 1.17
save("dice", dice)

# Step: a soft wooden pop.
n = int(SR * 0.09)
t = np.arange(n) / SR
f = 900 * np.exp(-t * 25) + 350
step = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, attack=0.002, decay=40)
save("step", step)

# Ladder: bright rising arpeggio.
lad = np.zeros(int(SR * 0.75))
for i, fr in enumerate([523.25, 659.25, 783.99, 1046.5, 1318.5]):
    place(lad, tone(fr, 0.35, decay=9), i * 0.08)
save("ladder", lad)

# Snake: hiss plus a falling slide whistle.
n = int(SR * 0.9)
t = np.arange(n) / SR
f = 900 * np.exp(-t * 2.2) + 120
whistle = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 1.5)
hiss = rng.standard_normal(n)
hiss = np.convolve(hiss, np.ones(3) / 3, mode="same") * np.exp(-t * 4) * 0.35
hiss *= np.clip(t / 0.03, 0, 1)
save("snake", whistle * 0.8 + hiss)

# Six: a two-note chime.
six = np.zeros(int(SR * 0.5))
place(six, tone(1046.5, 0.4, decay=7), 0)
place(six, tone(1568.0, 0.4, decay=7), 0.09)
save("six", six)

# Win: short fanfare ending on a held chord.
win = np.zeros(int(SR * 1.6))
for i, fr in enumerate([523.25, 523.25, 659.25, 783.99]):
    place(win, tone(fr, 0.25, decay=8, harmonics=(1, 0.5, 0.25, 0.1)), i * 0.12)
for fr in [523.25, 659.25, 783.99, 1046.5]:
    place(win, tone(fr, 1.1, decay=2.5, harmonics=(1, 0.5, 0.25, 0.1)), 0.5)
save("win", win)

# Tap: tiny UI click.
save("tap", click(0.04, 1500))
