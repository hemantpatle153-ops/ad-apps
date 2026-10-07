"""Synthesises the Ludo-only sound effects (capture, token home, token out).

Run from apps/snakes_ladders: python3 tool/gen_ludo_sounds.py (needs numpy)
"""
import wave
import numpy as np

SR = 22050


def env(n, attack=0.005, decay=6.0):
    t = np.arange(n) / SR
    return np.clip(t / attack, 0, 1) * np.exp(-decay * t)


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
    with wave.open(f"assets/sounds/{name}.wav", "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((sig * 32767).astype(np.int16).tobytes())


# Capture: a punchy knock then a quick falling "whoop".
n = int(SR * 0.55)
t = np.arange(n) / SR
f = 700 * np.exp(-t * 5) + 140
whoop = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, attack=0.004, decay=5)
knock = np.zeros(n)
place(knock, tone(180, 0.12, decay=30, harmonics=(1, 0.6, 0.3)), 0)
save("ludo_capture", whoop * 0.7 + knock)

# Token home: sparkly rising triad.
home = np.zeros(int(SR * 0.8))
for i, fr in enumerate([783.99, 987.77, 1174.66, 1567.98]):
    place(home, tone(fr, 0.45, decay=7, harmonics=(1, 0.2, 0.05)), i * 0.07)
save("ludo_home", home)

# Token out of the yard: short bright pop up.
n = int(SR * 0.18)
t = np.arange(n) / SR
f = 300 + 900 * (1 - np.exp(-t * 30))
save("ludo_out", np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, attack=0.002, decay=18))
