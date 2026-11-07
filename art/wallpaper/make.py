"""Рисует обои norka-dusk.png по norka-dusk.svg, но без ступенек градиента.

rsvg размывает пятна в 8 битах, и на тёмном фоне видны кольца. Здесь всё считается
в float, а при переводе в 8 бит добавляется лёгкий шум (дизеринг).
Запуск в WSL с Arch: /opt/rembg/bin/python art/wallpaper/make.py
"""
import pathlib

import numpy as np
from PIL import Image
from scipy import ndimage

here = pathlib.Path(__file__).resolve().parent
W, H = 3840, 2160
K = 4  # считаем в 4 раза мельче: картинка вся размытая, детали не теряются
w, h = W // K, H // K


def rgb(hex_color):
    return np.array([int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)])


y, x = np.mgrid[0:h, 0:w].astype(np.float64)
x, y = (x + 0.5) * K, (y + 0.5) * K

# Фон: диагональный градиент как linearGradient x1=0 y1=0 x2=1 y2=1
t = (x / W + y / H) / 2
stops = [(0, rgb("#0d0718")), (0.55, rgb("#160c2a")), (1, rgb("#0a0512"))]
image = np.zeros((h, w, 3))
for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
    part = np.clip((t - t0) / (t1 - t0), 0, 1)[..., None]
    inside = ((t >= t0) & (t <= t1))[..., None]
    image = np.where(inside, c0 + (c1 - c0) * part, image)


def ellipse(cx, cy, rx, ry, angle):
    a = np.radians(angle)
    dx, dy = x - cx, y - cy
    u = dx * np.cos(a) + dy * np.sin(a)
    v = -dx * np.sin(a) + dy * np.cos(a)
    return ((u / rx) ** 2 + (v / ry) ** 2 <= 1).astype(np.float64)


def group(blur, shapes):
    """Пятна группы с прозрачностью, потом гауссово размытие всей группы, как filter в SVG."""
    color = np.zeros((h, w, 3))
    alpha = np.zeros((h, w))
    for cx, cy, rx, ry, angle, fill, opacity in shapes:
        a = ellipse(cx, cy, rx, ry, angle) * opacity
        color = color * (1 - a[..., None]) + rgb(fill) * a[..., None]
        alpha = alpha * (1 - a) + a
    sigma = blur / K
    color = np.stack([ndimage.gaussian_filter(color[..., i], sigma) for i in range(3)], axis=-1)
    alpha = ndimage.gaussian_filter(alpha, sigma)
    return color, alpha


for blur, shapes in (
    (220, [(2850, 520, 980, 420, -18, "#4a2a86", .55), (760, 1720, 1100, 380, -10, "#3a1f6e", .5)]),
    (120, [(3040, 430, 520, 120, -22, "#7a4fd0", .32), (2260, 1180, 420, 80, -24, "#e98ab4", .09)]),
):
    color, alpha = group(blur, shapes)
    image = image * (1 - alpha[..., None]) + color

# Увеличиваем до 4K в float, затем 8 бит с треугольным шумом в полтона
big = np.stack([
    np.asarray(Image.fromarray(image[..., i].astype(np.float32), "F").resize((W, H), Image.Resampling.BICUBIC))
    for i in range(3)
], axis=-1)
rng = np.random.default_rng(7)
noise = rng.random((H, W, 3)) - rng.random((H, W, 3))
out = np.clip(big * 255 + noise * 0.75 + 0.5, 0, 255).astype(np.uint8)
Image.fromarray(out, "RGB").save(here / "norka-dusk.png", optimize=True)
print("norka-dusk.png", out.shape)
