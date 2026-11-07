"""Приветствие NorkaOS в терминале: лого и Норка полублоками в truecolor, под ними «Welcome to NorkaOS».

Запуск в WSL с Arch (нужны librsvg и pillow): /opt/rembg/bin/python art/terminal/make.py
Результат: art/terminal/hello.ansi (приветствие), logo.ansi (лого для fastfetch), preview.png (как это выглядит, в git не идёт)
"""
import io
import pathlib
import subprocess

from PIL import Image

here = pathlib.Path(__file__).resolve().parent
art = here.parent
ESC = "\033"
LAVENDER = (201, 184, 234)


def pixels(image, width, height):
    # Уменьшаем с учётом прозрачности, иначе края темнеют от цвета прозрачных пикселей
    small = image.convert("RGBa").resize((width, height), Image.Resampling.LANCZOS).convert("RGBA")
    return small


def svg(path, size):
    png = subprocess.run(["rsvg-convert", "-w", str(size * 8), str(art / path)], check=True, capture_output=True).stdout
    return Image.open(io.BytesIO(png)).convert("RGBA")


def rows(image):
    """Каждая клетка терминала это два пикселя: верхний цветом символа ▀, нижний фоном."""
    w, h = image.size
    px = image.load()
    lines = []
    for y in range(0, h, 2):
        cells = []
        for x in range(w):
            top = px[x, y]
            bottom = px[x, y + 1] if y + 1 < h else (0, 0, 0, 0)
            t, b = top[3] >= 128, bottom[3] >= 128
            if t and b:
                cells.append(f"{ESC}[38;2;{top[0]};{top[1]};{top[2]};48;2;{bottom[0]};{bottom[1]};{bottom[2]}m▀")
            elif t:
                cells.append(f"{ESC}[49;38;2;{top[0]};{top[1]};{top[2]}m▀")
            elif b:
                cells.append(f"{ESC}[49;38;2;{bottom[0]};{bottom[1]};{bottom[2]}m▄")
            else:
                cells.append(f"{ESC}[0m ")
        lines.append("".join(cells) + f"{ESC}[0m")
    return lines


def blank(width, count):
    return [" " * width] * count


logo_px = 26
logo = pixels(svg("logo/norka-icon.svg", logo_px), logo_px, logo_px)

# Для терминала только голова и руки: целиком Норка в 40 строк не разглядеть
mascot = Image.open(art / "mascot/norka-shy.png").convert("RGBA")
bust = mascot.crop((0, 0, 490, 560))
bust_h = 40
bust = pixels(bust, round(bust.width * bust_h / bust.height), bust_h)

left, right = rows(logo), rows(bust)
gap = 4
top_pad = (len(right) - len(left)) // 2
left = blank(logo_px, top_pad) + left + blank(logo_px, len(right) - len(left) - top_pad)
width = logo_px + gap + bust.width
text = "Welcome to NorkaOS"
r, g, b = LAVENDER
lines = [" " + l + " " * gap + rr for l, rr in zip(left, right)]
lines += ["", " " * (1 + (width - len(text)) // 2) + f"{ESC}[1;38;2;{r};{g};{b}m{text}{ESC}[0m", ""]
(here / "hello.ansi").write_text("\n".join(lines) + "\n", encoding="utf-8")
(here / "logo.ansi").write_text("\n".join(rows(logo)) + "\n", encoding="utf-8")
print("hello.ansi", width + 1, "x", len(lines))

# Превью: клетка 8x16, каждый полублок квадрат 8x8
preview = Image.new("RGBA", ((width + 2) * 8, (len(right) + 4) * 16), (18, 12, 28, 255))
for img, x0, y0 in ((logo, 8, top_pad * 16), (bust, 8 + (logo_px + gap) * 8, 0)):
    big = img.resize((img.width * 8, img.height * 8), Image.Resampling.NEAREST)
    preview.alpha_composite(big, (x0, y0))
preview.save(here / "preview.png")
