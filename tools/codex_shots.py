"""Store screenshots from Codex frames: each frame (store/codex/pN_*.png) is a
Codex-drawn design with the headline text and a phone whose screen is pure
green. The real game capture is placed into the green area, then the canvas is
widened to 2868x1320 by extending its plain left/right edges.

  python tools/codex_shots.py <raw shots dir>   # writes store/screenshots_marketing/mN_*.png
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
W, H = 2868, 1320
PAIRS = ["menu", "cab", "side", "result", "large", "small", "wrecker", "towres"]


def place(frame: Image.Image, shot: Image.Image) -> Image.Image:
    a = np.asarray(frame.convert("RGB")).astype(int)
    green = (a[..., 1] > 170) & (a[..., 0] < 120) & (a[..., 2] < 120)
    ys, xs = np.nonzero(green)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    # grow the mask a little so no green fringe is left on the rounded corners
    mask = Image.fromarray((green * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5))
    fill = shot.convert("RGB").resize((x1 - x0 + 4, y1 - y0 + 4), Image.LANCZOS)
    layer = frame.convert("RGB").copy()
    layer.paste(fill, (x0 - 2, y0 - 2))
    return Image.composite(layer, frame.convert("RGB"), mask)


def widen(img: Image.Image) -> Image.Image:
    # Codex frames are 2:1; scale to the full width and trim the top and bottom evenly
    s = W / img.width
    img = img.resize((W, round(img.height * s)), Image.LANCZOS)
    y = (img.height - H) // 2
    return img.crop((0, y, W, y + H))


if __name__ == "__main__":
    raw = Path(sys.argv[1])
    dst = ROOT / "store" / "screenshots_marketing"
    dst.mkdir(parents=True, exist_ok=True)
    for i, n in enumerate(PAIRS, 1):
        f = ROOT / "store" / "codex" / f"p{i}_{n}.png"
        if not f.exists():
            print("skip", f.name)
            continue
        out = widen(place(Image.open(f), Image.open(raw / f"m{i}_{n}.png")))
        out.save(dst / f"m{i}_{n}.png")
        print("wrote", f"m{i}_{n}.png", out.size)
