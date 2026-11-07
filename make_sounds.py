"""Synthesises the pets' sounds from scratch (no samples): Thea's hiss, Ivan's mew,
Kai's boof, and a little tap for knocked-over things. Writes sounds/*.wav."""
import wave
from pathlib import Path

import numpy as np

RATE = 44100
OUT = Path(__file__).parent / "sounds"
rng = np.random.default_rng(7)


def env(n, attack, release):
    e = np.ones(n)
    a, r = int(attack * RATE), int(release * RATE)
    e[:a] = np.linspace(0, 1, a)
    e[n - r:] *= np.linspace(1, 0, r) ** 1.6
    return e


def save(name, x, gain=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    data = (x * 32767).astype(np.int16)
    OUT.mkdir(exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def hiss(seconds=0.75):
    n = int(seconds * RATE)
    noise = rng.normal(0, 1, n)
    bright = np.diff(noise, prepend=0)  # tilt toward high frequencies
    bright = np.diff(bright, prepend=0)
    shaped = bright * (0.6 + 0.4 * np.sin(np.linspace(0, 9 * np.pi, n)) ** 2)  # a little flutter
    return shaped * env(n, 0.04, 0.45)


def mew(f_start=720, f_peak=1050, f_end=640, seconds=0.5):
    n = int(seconds * RATE)
    t = np.linspace(0, 1, n)
    f0 = np.where(t < 0.35, f_start + (f_peak - f_start) * (t / 0.35), f_peak + (f_end - f_peak) * ((t - 0.35) / 0.65))
    f0 *= 1 + 0.012 * np.sin(2 * np.pi * 7 * t * seconds)  # gentle vibrato
    phase = 2 * np.pi * np.cumsum(f0) / RATE
    formant = 1100 + 900 * np.sin(np.pi * t)  # "m-ee-ow" mouth opening and closing
    x = np.zeros(n)
    for k in range(1, 10):
        weight = np.exp(-((k * f0 - formant) ** 2) / (2 * 520**2)) + 0.08 / k
        x += weight * np.sin(k * phase)
    return x * env(n, 0.05, 0.22)


def boof(f=190, seconds=0.16):
    n = int(seconds * RATE)
    t = np.linspace(0, 1, n)
    f0 = f * (1.15 - 0.3 * t)
    phase = 2 * np.pi * np.cumsum(f0) / RATE
    x = sum(np.sin(k * phase) / k**0.7 for k in range(1, 12))
    x = np.tanh(2.2 * x) + 0.25 * rng.normal(0, 1, n)
    return x * env(n, 0.006, 0.09)


def tap():
    n = int(0.09 * RATE)
    t = np.arange(n) / RATE
    return (np.sin(2 * np.pi * 1800 * t) + 0.5 * np.sin(2 * np.pi * 2900 * t)) * np.exp(-t * 55)


if __name__ == "__main__":
    save("hiss", hiss(), 0.7)
    save("mew", np.concatenate([mew(), np.zeros(int(0.05 * RATE))]), 0.75)
    gap = np.zeros(int(0.09 * RATE))
    save("boof", np.concatenate([boof(), gap, boof(205, 0.13)]), 0.75)
    save("tap", tap(), 0.6)
    print(sorted(p.name for p in OUT.glob("*.wav")))
