"""Вырезает Норку из сгенерированных артов: убирает фон и режет лист с позами.

Запуск в WSL с Arch: /opt/rembg/bin/python art/mascot/make.py
Нужен venv с rembg[cpu] и pillow, модель isnet-anime скачается сама при первом запуске.
Результат: art/mascot/norka-shy.png, norka-peek.png, norka-jump.png с прозрачным фоном.
"""
import pathlib

import numpy as np
from PIL import Image, ImageChops, ImageFilter
from scipy import ndimage
from rembg import new_session, remove

here = pathlib.Path(__file__).resolve().parent
src = here / "source"
# Модель обучена на аниме-персонажах: тёмное худи на тёмном фоне отделяет лучше общей
session = new_session("isnet-anime")


def cut(image, name, keep_bright=0):
    result = remove(image, session=session, post_process_mask=True)
    if keep_bright:
        # Нейросеть иногда принимает светлые розовые уши на чёрном за свечение фона.
        # Всё заметно светлее фона возвращаем в маску
        bright = np.array(image.convert("L").filter(ImageFilter.MedianFilter(5))) > keep_bright
        # Мелкие светлые пятна вокруг (блики фона) выкидываем, остаются только крупные куски вроде ушей
        labels, count = ndimage.label(bright)
        sizes = ndimage.sum(bright, labels, range(1, count + 1))
        big = np.isin(labels, 1 + np.flatnonzero(sizes > 3000))
        alpha = ImageChops.lighter(result.getchannel("A"), Image.fromarray((big * 255).astype(np.uint8)))
        # Цвет берём из оригинала: под тем, что нейросеть сочла фоном, она его обнулила
        result = image.convert("RGBA")
        result.putalpha(alpha)
    result = result.crop(result.getbbox())
    result.save(here / f"{name}.png", optimize=True)
    print(name, result.size)


cut(Image.open(src / "norka-shy.png").convert("RGB"), "norka-shy")

sheet = Image.open(src / "norka-peek-jump.png").convert("RGB")
# Слева от стенки (x≈620) Норка выглядывает, справа прыгает
cut(sheet.crop((0, 0, 612, sheet.height)), "norka-peek")
cut(sheet.crop((632, 0, sheet.width, sheet.height)), "norka-jump", keep_bright=110)
