"""Аватар пользователя: голова Норки из norka-shy.png на тёмно-фиолетовом фоне.

Запуск в WSL с Arch: /opt/rembg/bin/python art/mascot/face.py
Результат: art/mascot/norka-face.png, 256x256. Plasma и SDDM сами обрезают его кругом
"""
import pathlib

from PIL import Image

here = pathlib.Path(__file__).resolve().parent
size = 256

shy = Image.open(here / "norka-shy.png").convert("RGBA")
# Голова с ушами и колокольчиком, Норка чуть смещена влево: справа уши
head = shy.crop((40, 10, 460, 430)).resize((size, size), Image.Resampling.LANCZOS)

face = Image.new("RGBA", (size, size))
# Вертикальный градиент как на обоях: сверху темнее
for y in range(size):
    t = y / (size - 1)
    color = tuple(round(a + (b - a) * t) for a, b in zip((28, 18, 46), (74, 52, 112))) + (255,)
    face.paste(color, (0, y, size, y + 1))
face.alpha_composite(head)
face.convert("RGB").save(here / "norka-face.png", optimize=True)
print("norka-face.png", face.size)
