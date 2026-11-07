"""Рисует курсоры NorkaOS: пушистую стрелку и крысиную лапу вместо руки.

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
PAD = "#f2a7c9"
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


def arrow_svg():
    tip = (28, 20)
    shape = [tip, (28, 196), (78, 152), (112, 226), (146, 210), (114, 140), (182, 136)]
    path = fluffy(shape, smooth_from=tip, smooth_len=40)
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
<defs><linearGradient id="f" x1="0" y1="0" x2="1" y2="1">
<stop offset="0" stop-color="{FUR}"/><stop offset="1" stop-color="{FUR_DARK}"/></linearGradient></defs>
<path d="{path}" fill="url(#f)" stroke="{LINE}" stroke-width="9" stroke-linejoin="round"/>
</svg>"""


def paw_svg():
    # Крысиная передняя лапа указывает вверх: длинный палец, три поджатых, пушистое запястье
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
<defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="{FUR}"/><stop offset="1" stop-color="{FUR_DARK}"/></linearGradient></defs>
<g stroke="{LINE}" stroke-width="9" stroke-linejoin="round" stroke-linecap="round" fill="url(#f)">
<path d="{fluffy([(70, 170), (196, 170), (190, 248), (76, 248)], tuft=6, step=16)}"/>
<path d="M92 26 C78 26 74 38 74 50 L74 150 L112 150 L112 50 C112 38 106 26 92 26 Z"/>
<ellipse cx="128" cy="124" rx="24" ry="30"/>
<ellipse cx="160" cy="130" rx="22" ry="28"/>
<ellipse cx="188" cy="142" rx="19" ry="24"/>
<path d="M66 132 C66 104 92 96 128 100 C170 102 210 120 210 158 C210 196 176 212 132 212 C92 212 66 196 66 158 Z"/>
</g>
<g fill="{PAD}">
<ellipse cx="93" cy="44" rx="11" ry="12"/>
<ellipse cx="128" cy="106" rx="11" ry="9"/>
<ellipse cx="160" cy="112" rx="10" ry="8"/>
<ellipse cx="188" cy="126" rx="9" ry="7"/>
<ellipse cx="138" cy="166" rx="34" ry="24"/>
</g>
</svg>"""


# Имя курсора → картинка, точка клика в долях от размера, синонимы
CURSORS = {
    "default": (arrow_svg, (28 / 256, 20 / 256), ["left_ptr", "arrow", "top_left_arrow"]),
    "pointer": (paw_svg, (92 / 256, 24 / 256), ["hand1", "hand2", "pointing_hand",
                                                 "9d800788f1b08800ae810202380a0822",
                                                 "e29285e634086352946a0e7090d73106"]),
}


def build(dest):
    theme = pathlib.Path(dest) / "NorkaOS-Paw"
    (theme / "cursors").mkdir(parents=True, exist_ok=True)
    (theme / "index.theme").write_text(
        "[Icon Theme]\nName=NorkaOS Paw\nComment=Пушистая стрелка и крысиная лапа\nInherits=breeze_cursors\n",
        encoding="utf-8",
    )
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for name, (draw, (hx, hy), aliases) in CURSORS.items():
            svg = tmp / f"{name}.svg"
            svg.write_text(draw(), encoding="utf-8")
            lines = []
            for size in SIZES:
                png = tmp / f"{name}-{size}.png"
                subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), "-o", str(png), str(svg)], check=True)
                lines.append(f"{size} {round(hx * size)} {round(hy * size)} {png}")
            conf = tmp / f"{name}.conf"
            conf.write_text("\n".join(lines) + "\n", encoding="utf-8")
            subprocess.run(["xcursorgen", str(conf), str(theme / "cursors" / name)], check=True)
            for alias in aliases:
                link = theme / "cursors" / alias
                link.unlink(missing_ok=True)
                link.symlink_to(name)
            # Превью для проверки глазами
            subprocess.run(["rsvg-convert", "-w", "256", "-h", "256", "-o",
                            str(pathlib.Path(__file__).parent / f"preview-{name}.png"), str(svg)], check=True)


build(sys.argv[1])
