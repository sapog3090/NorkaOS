"""Звуки NorkaOS: мягкие деревянные звоночки и короткий писк Норки, синтезированы кодом.

Запуск (нужны numpy и vorbis-tools): python art/sounds/make.py ПАПКА, при сборке пакета темы это /usr/share/sounds
В ПАПКЕ появится тема norkaos/stereo/*.oga и index.theme. Остальные звуки берутся из Ocean
"""
import pathlib
import subprocess
import sys
import tempfile
import wave

import numpy as np

RATE = 48000
out = pathlib.Path(sys.argv[1]) / "norkaos"


def note(freq, length, start=0.0, volume=0.5, decay=6.0):
    """Звоночек: основной тон и тихие обертоны, быстрая атака и плавное затухание."""
    t = np.arange(int(RATE * length)) / RATE
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 2.01 * t) + 0.12 * np.sin(2 * np.pi * freq * 3.98 * t)
    envelope = np.minimum(t / 0.006, 1) * np.exp(-decay * t)
    sound = np.zeros(int(RATE * start) + len(t))
    sound[int(RATE * start):] += tone * envelope * volume
    return sound


def squeak(f0, f1, length, start=0.0, volume=0.35):
    """Писк: тон скользит вверх, лёгкое дрожание как у живого зверька."""
    t = np.arange(int(RATE * length)) / RATE
    freq = f0 + (f1 - f0) * (t / length) ** 0.6 + 40 * np.sin(2 * np.pi * 28 * t)
    phase = 2 * np.pi * np.cumsum(freq) / RATE
    tone = np.sin(phase) + 0.25 * np.sin(2 * phase)
    envelope = np.sin(np.pi * t / length) ** 1.5
    sound = np.zeros(int(RATE * start) + len(t))
    sound[int(RATE * start):] += tone * envelope * volume
    return sound


def mix(*parts):
    length = max(len(p) for p in parts)
    total = np.zeros(length + RATE // 10)
    for p in parts:
        total[:len(p)] += p
    peak = np.max(np.abs(total))
    return total / peak * 0.7 if peak > 0 else total


# Ноты пентатоники до мажор, звучат дружелюбно в любом порядке
C5, D5, E5, G5, A5, C6, E6 = 523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1318.5
SOUNDS = {
    "desktop-login": mix(note(C5, 1.2), note(E5, 1.2, 0.12), note(G5, 1.2, 0.24), note(C6, 1.4, 0.36), squeak(1800, 2600, 0.12, 0.9, 0.2)),
    "desktop-logout": mix(note(G5, 1.0), note(E5, 1.0, 0.14), note(C5, 1.3, 0.28)),
    "message-new-instant": mix(note(E6, 0.6, volume=0.4, decay=9), note(C6, 0.7, 0.09, 0.4, 9)),
    "dialog-information": mix(note(A5, 0.7, decay=8), note(E6, 0.8, 0.1, 0.35, 8)),
    "dialog-warning": mix(note(G5, 0.6, decay=8), note(G5, 0.7, 0.16, 0.45, 8)),
    "dialog-error": mix(note(E5, 0.5, decay=9), note(C5, 0.8, 0.15, 0.5, 7)),
    "dialog-question": mix(note(C5, 0.5, decay=9), note(G5, 0.7, 0.12, 0.45, 8)),
    "device-added": mix(note(C5, 0.5, decay=9), note(G5, 0.7, 0.1, 0.45, 8)),
    "device-removed": mix(note(G5, 0.5, decay=9), note(C5, 0.7, 0.1, 0.45, 8)),
    "completion-success": mix(note(C6, 0.5, decay=9), note(E6, 0.8, 0.08, 0.4, 8), squeak(2000, 2900, 0.1, 0.3, 0.18)),
    "trash-empty": mix(note(D5, 0.4, decay=12), note(D5, 0.4, 0.07, 0.3, 12)),
    "bell": mix(note(A5, 0.6, decay=8)),
    "norka-squeak": mix(squeak(1600, 2700, 0.14), squeak(1900, 3000, 0.11, 0.17, 0.3)),
}

(out / "stereo").mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    for name, data in SOUNDS.items():
        wav = pathlib.Path(tmp) / f"{name}.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            pcm = (np.repeat(data[:, None], 2, axis=1) * 32767).astype("<i2")
            w.writeframes(pcm.tobytes())
        subprocess.run(["oggenc", "-Q", "-q", "4", "-o", str(out / "stereo" / f"{name}.oga"), str(wav)], check=True)

(out / "index.theme").write_text(
    "[Sound Theme]\nName=NorkaOS\nName[ru]=NorkaOS\nComment=Soft chimes and Norka squeaks\n"
    "Comment[ru]=Мягкие звоночки и писк Норки\nInherits=ocean\nDirectories=stereo\n\n[stereo]\nOutputProfile=stereo\n",
    encoding="utf-8",
)
print(len(SOUNDS), "sounds in", out)
