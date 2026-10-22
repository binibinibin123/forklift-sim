"""절차적 텍스처 생성 → textures/*.png (타일링). 실행: python3 tools/make_textures.py"""
import os, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "textures")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def tile_noise(n, octaves=5, persistence=0.55, seed=0):
    """타일링되는 값 노이즈(0..1)."""
    r = np.random.default_rng(seed)
    out = np.zeros((n, n), dtype=np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        cells = 4 * (2 ** o)
        g = r.random((cells, cells)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8))
        # 타일링을 위해 3x3으로 이어 붙인 뒤 가운데를 확대
        big = Image.new("L", (cells * 3, cells * 3))
        for i in range(3):
            for j in range(3):
                big.paste(img, (i * cells, j * cells))
        big = big.resize((n * 3, n * 3), Image.BICUBIC)
        layer = np.asarray(big.crop((n, n, 2 * n, 2 * n)), dtype=np.float32) / 255.0
        out += layer * amp
        total += amp
        amp *= persistence
    return out / total


def normal_from_height(h, strength=2.0):
    n = h.shape[0]
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nx, ny, nz = -dx, -dy, np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([(nx / l + 1) * 0.5, (ny / l + 1) * 0.5, (nz / l + 1) * 0.5], axis=-1)
    return Image.fromarray((rgb * 255).astype(np.uint8))


def save(img, name):
    img.save(os.path.join(OUT, name))
    print(name, img.size)


def asphalt(n=1024):
    base = tile_noise(n, 6, 0.6, seed=1)
    fine = tile_noise(n, 8, 0.5, seed=2)
    speck = rng.random((n, n)).astype(np.float32)
    v = 0.30 + 0.10 * (base - 0.5) + 0.12 * (fine - 0.5) + 0.05 * (speck - 0.5)
    v = np.clip(v, 0, 1)
    rgb = np.stack([v * 0.98, v, v * 1.02], axis=-1)
    save(Image.fromarray((rgb * 255).astype(np.uint8)), "asphalt.png")
    save(normal_from_height(fine * 0.6 + speck * 0.4, 1.5), "asphalt_n.png")


def concrete(n=512):
    base = tile_noise(n, 5, 0.6, seed=3)
    v = 0.62 + 0.14 * (base - 0.5)
    img = Image.fromarray((np.clip(v, 0, 1) * 255).astype(np.uint8)).convert("RGB")
    d = ImageDraw.Draw(img)
    for _ in range(40):  # 얼룩
        x, y = rng.integers(0, n, 2)
        r = int(rng.integers(10, 60))
        c = int(rng.integers(120, 160))
        d.ellipse((x - r, y - r, x + r, y + r), fill=(c, c, c - 4))
    img = img.filter(ImageFilter.GaussianBlur(3))
    base_img = Image.fromarray((np.clip(v, 0, 1) * 255).astype(np.uint8)).convert("RGB")
    img = Image.blend(base_img, img, 0.5)
    save(img, "concrete.png")


def corrugated(n=512):
    """창고 벽 골판 금속(세로 주름)."""
    x = np.arange(n)
    wave = (np.sin(x / n * 2 * math.pi * 16) * 0.5 + 0.5).astype(np.float32)
    h = np.tile(wave, (n, 1))
    dirt = tile_noise(n, 5, 0.6, seed=4)
    v = 0.72 + 0.10 * (h - 0.5) - 0.08 * (dirt - 0.5)
    rgb = np.stack([v * 0.93, v * 0.95, v], axis=-1)
    save(Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)), "corrugated.png")
    save(normal_from_height(h * 0.3, 2.5), "corrugated_n.png")


def wood(n=512):
    grain = tile_noise(n, 6, 0.5, seed=5)
    y = np.arange(n)[:, None]
    rings = (np.sin((grain * 14 + y / 9.0)) * 0.5 + 0.5)
    v = 0.52 + 0.14 * (rings - 0.5) + 0.1 * (grain - 0.5)
    rgb = np.stack([v * 1.15, v * 0.9, v * 0.6], axis=-1)
    save(Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)), "wood.png")


def paint(n=512, color=(1.0, 0.62, 0.08), name="paint_orange.png"):
    """도장 금속: 미세 긁힘과 먼지."""
    dirt = tile_noise(n, 6, 0.55, seed=6)
    scratch = rng.random((n, n)).astype(np.float32)
    v = 1.0 - 0.10 * (dirt - 0.5) - 0.04 * (scratch > 0.995)
    rgb = np.stack([color[0] * v, color[1] * v, color[2] * v], axis=-1)
    save(Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)), name)


def tire(n=256):
    """타이어 트레드(원통 옆면용, 가로로 반복)."""
    img = Image.new("RGB", (n, n), (22, 22, 23))
    d = ImageDraw.Draw(img)
    for i in range(0, n, 32):
        d.rectangle((i + 4, 0, i + 18, n), fill=(14, 14, 15))
        d.polygon([(i + 18, 0), (i + 28, n // 2), (i + 18, n)], fill=(16, 16, 17))
    save(img, "tire.png")


def chainlink(n=256):
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = 32
    for x in range(-s, n + s, s):
        for y in range(-s, n + s, s):
            d.line((x, y + s // 2, x + s // 2, y), fill=(190, 192, 196, 255), width=3)
            d.line((x + s // 2, y, x + s, y + s // 2), fill=(170, 172, 176, 255), width=3)
            d.line((x, y + s // 2, x + s // 2, y + s), fill=(170, 172, 176, 255), width=3)
            d.line((x + s // 2, y + s, x + s, y + s // 2), fill=(190, 192, 196, 255), width=3)
    save(img, "chainlink.png")


def clouds(n=1024):
    base = tile_noise(n, 6, 0.55, seed=9)
    v = np.clip((base - 0.45) * 2.2, 0, 1)
    img = Image.fromarray((v * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    rgba = Image.merge("RGBA", (img.point(lambda p: 255), img.point(lambda p: 255), img.point(lambda p: 255), img))
    save(rgba, "clouds.png")


def drum_label(n=512):
    img = Image.new("RGB", (n, n), (22, 70, 150))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 150, n, 165), fill=(16, 55, 120))
    d.rectangle((0, 340, n, 355), fill=(16, 55, 120))
    d.rectangle((60, 190, 260, 310), fill=(235, 235, 230))
    try:
        f = ImageFont.truetype(os.path.join(ROOT, "fonts", "GowunDodum-Regular.ttf"), 34)
        d.text((80, 205), "실기 시험용", fill=(30, 30, 30), font=f)
        d.text((80, 250), "200 L", fill=(30, 30, 30), font=f)
    except Exception:
        pass
    noise = tile_noise(n, 5, 0.6, seed=11)
    arr = np.asarray(img).astype(np.float32) * (0.9 + 0.2 * noise[..., None])
    save(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)), "drum.png")


def cardboard(n=256):
    base = tile_noise(n, 5, 0.6, seed=12)
    v = 0.68 + 0.08 * (base - 0.5)
    rgb = np.stack([v * 1.05, v * 0.88, v * 0.65], axis=-1)
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.rectangle((20, 60, 110, 120), outline=(90, 70, 45), width=3)
    d.line((0, n // 2, n, n // 2), fill=(120, 95, 60), width=2)
    save(img, "cardboard.png")


def line_mask(n=512):
    """바닥 선 마모 마스크(알파)."""
    base = tile_noise(n, 5, 0.5, seed=13)
    a = np.clip(0.55 + 0.9 * (base - 0.5), 0, 1)
    img = Image.new("RGBA", (n, n), (255, 255, 255, 255))
    img.putalpha(Image.fromarray((a * 255).astype(np.uint8)))
    save(img, "line_wear.png")


if __name__ == "__main__":
    asphalt(); concrete(); corrugated(); wood(); paint(); paint(512, (0.16, 0.16, 0.17), "paint_dark.png")
    paint(512, (0.22, 0.45, 0.2), "paint_green.png")
    tire(); chainlink(); clouds(); drum_label(); cardboard(); line_mask()
