"""Собирает картинки меню загрузки из обоев и лого.

Запуск в WSL с Arch (нужен librsvg): python art/boot/make.py
Результат: art/boot/grub-background.png, art/boot/select_c.png, art/boot/syslinux-splash.png
"""
import pathlib
import re
import subprocess

here = pathlib.Path(__file__).resolve().parent
art = here.parent


def inner(svg_path):
    """Содержимое SVG без внешнего тега и его viewBox."""
    text = (art / svg_path).read_text(encoding="utf-8")
    view_box = re.search(r'viewBox="([^"]+)"', text).group(1)
    body = re.sub(r"^.*?<svg[^>]*>", "", text, count=1, flags=re.S)
    body = re.sub(r"</svg>\s*$", "", body)
    return view_box, body


def compose(width, height, logo_size, logo_top, ids):
    wall_box, wall = inner("wallpaper/norka-dusk.svg")
    logo_box, logo = inner("logo/norka-logo.svg")
    # id в двух вставках не должны совпадать, поэтому у лого добавляем приставку
    for old in set(re.findall(r'id="([^"]+)"', logo)):
        logo = logo.replace(f'id="{old}"', f'id="{ids}{old}"').replace(f"url(#{old})", f"url(#{ids}{old})")
    x = (width - logo_size) // 2
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}">'
        f'<svg width="{width}" height="{height}" viewBox="{wall_box}" preserveAspectRatio="xMidYMid slice">{wall}</svg>'
        f'<svg x="{x}" y="{logo_top}" width="{logo_size}" height="{logo_size}" viewBox="{logo_box}">{logo}</svg>'
        "</svg>"
    )


def render(svg, name):
    src = here / (name + ".svg")
    src.write_text(svg, encoding="utf-8")
    subprocess.run(["rsvg-convert", "-o", str(here / (name + ".png")), str(src)], check=True)
    src.unlink()


render(compose(1920, 1080, 360, 70, "g"), "grub-background")
render(compose(640, 480, 150, 4, "s"), "syslinux-splash")
# Подсветка выбранного пункта в GRUB: полупрозрачная фиолетовая полоса, GRUB растягивает её
render(
    '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'
    '<rect width="8" height="8" fill="#7a4fd0" fill-opacity=".55"/></svg>',
    "select_c",
)
