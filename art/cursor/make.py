"""Рисует курсоры NorkaOS: пушистую стрелку, которая над ссылками крутится вокруг кончика.

Запуск в WSL с Arch (нужны librsvg и xorg-xcursorgen): python art/cursor/make.py <папка>
В папке появится тема курсоров NorkaOS-Paw, остальные курсоры она берёт из Breeze.
"""
import math
import pathlib
import subprocess
import sys
import tempfile

FUR = "#e4d6ff"
FUR_DARK = "#b794f4"
LINE = "#241338"
SIZES = (24, 32, 48, 64)


def fluffy(points, tuft=7.0, step=13.0, smooth_from=None, smooth_len=0.0):
    """Контур многоугольника с мягкими завитками шерсти наружу. Возле smooth_from шерсти нет, чтобы остриё было точным."""
    n = len(points)
    # Направление обхода нужно, чтобы шерсть торчала наружу
    area = sum(points[i][0] * points[(i + 1) % n][1] - points[(i + 1) % n][0] * points[i][1] for i in range(n))
    sign = 1 if area > 0 else -1
    parts = [f"M{points[0][0]:.1f},{points[0][1]:.1f}"]
    for i in range(n):
        (x1, y1), (x2, y2) = points[i], points[(i + 1) % n]
        length = math.hypot(x2 - x1, y2 - y1)
        dx, dy = (x2 - x1) / length, (y2 - y1) / length
        nx, ny = sign * dy, -sign * dx
        count = max(1, int(length // step))
        for k in range(count):
            ex, ey = x1 + (x2 - x1) * (k + 1) / count, y1 + (y2 - y1) * (k + 1) / count
            mx, my = x1 + (x2 - x1) * (k + 0.5) / count, y1 + (y2 - y1) * (k + 0.5) / count
            if smooth_from and math.hypot(mx - smooth_from[0], my - smooth_from[1]) < smooth_len:
                parts.append(f"L{ex:.1f},{ey:.1f}")
                continue
            # Завиток чуть завален по ходу контура, так шерсть выглядит приглаженной
            h = tuft * (0.8 + 0.3 * math.sin(k * 2.3 + i))
            cx, cy = mx + nx * h * 2 + dx * h * 0.8, my + ny * h * 2 + dy * h * 0.8
            parts.append(f"Q{cx:.1f},{cy:.1f} {ex:.1f},{ey:.1f}")
    return " ".join(parts) + " Z"


TIP = (28, 20)


def arrow_svg(angle=0.0, canvas=256):
    """Стрелка, повёрнутая вокруг кончика. canvas больше 256 оставляет место для поворота, кончик тогда в центре."""
    shape = [TIP, (28, 196), (78, 152), (112, 226), (146, 210), (114, 140), (182, 136)]
    path = fluffy(shape, smooth_from=TIP, smooth_len=40)
    left, top = (0, 0) if canvas == 256 else (TIP[0] - canvas / 2, TIP[1] - canvas / 2)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="{left} {top} {canvas} {canvas}">
<defs><linearGradient id="f" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="{FUR}"/><stop offset="1" stop-color="{FUR_DARK}"/></linearGradient></defs>
<g transform="rotate({angle:.2f} {TIP[0]} {TIP[1]})">
<path d="{path}" fill="url(#f)" stroke="{LINE}" stroke-width="9" stroke-linejoin="round"/>
</g>
</svg>"""


def default_frames():
    # Один кадр, кончик в левом верхнем углу
    return [(arrow_svg(), 1, (TIP[0] / 256, TIP[1] / 256), 0)]


def pointer_frames():
    # Над ссылкой стрелка плавно делает оборот вокруг кончика и замирает. Картинка вдвое больше,
    # чтобы стрелке было где развернуться, поэтому кончик и точка клика в центре
    spin, frames = 28, []
    for i in range(spin):
        t = i / spin
        eased = t * t * (3 - 2 * t)
        frames.append((arrow_svg(360 * eased, 512), 2, (0.5, 0.5), 22))
    frames.append((arrow_svg(0, 512), 2, (0.5, 0.5), 1100))
    return frames


# Имя курсора → кадры, синонимы
CURSORS = {
    "default": (default_frames, ["left_ptr", "arrow", "top_left_arrow"]),
    "pointer": (pointer_frames, ["hand1", "hand2", "pointing_hand",
                                 "9d800788f1b08800ae810202380a0822",
                                 "e29285e634086352946a0e7090d73106"]),
}


def build(dest):
    theme = pathlib.Path(dest) / "NorkaOS-Paw"
    (theme / "cursors").mkdir(parents=True, exist_ok=True)
    (theme / "index.theme").write_text(
        "[Icon Theme]\nName=NorkaOS Paw\nComment=Пушистая стрелка, над ссылками крутится\nInherits=breeze_cursors\n",
        encoding="utf-8",
    )
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for name, (make_frames, aliases) in CURSORS.items():
            lines = []
            for n, (svg_text, scale, (hx, hy), delay) in enumerate(make_frames()):
                svg = tmp / f"{name}-{n}.svg"
                svg.write_text(svg_text, encoding="utf-8")
                for size in SIZES:
                    px = size * scale
                    png = tmp / f"{name}-{n}-{size}.png"
                    subprocess.run(["rsvg-convert", "-w", str(px), "-h", str(px), "-o", str(png), str(svg)], check=True)
                    line = f"{size} {round(hx * px)} {round(hy * px)} {png}"
                    lines.append(f"{line} {delay}" if delay else line)
                if n == 0:
                    # Превью для проверки глазами
                    subprocess.run(["rsvg-convert", "-w", "256", "-h", "256", "-o",
                                    str(pathlib.Path(__file__).parent / f"preview-{name}.png"), str(svg)], check=True)
            conf = tmp / f"{name}.conf"
            conf.write_text("\n".join(lines) + "\n", encoding="utf-8")
            subprocess.run(["xcursorgen", str(conf), str(theme / "cursors" / name)], check=True)
            for alias in aliases:
                link = theme / "cursors" / alias
                link.unlink(missing_ok=True)
                link.symlink_to(name)


build(sys.argv[1])
