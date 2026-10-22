"""스토어 스크린샷(6.9" 가로 2868x1320): 절차 배경 + 실제 화면 + 왼쪽 문구 → store/screenshots_marketing/.
실행: python3 tools/make_marketing.py [원본 스크린샷 폴더]  (기본 store/screenshots/raw)
아이콘: raw/icon_raw.png → icon.png (1024)."""
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 2868, 1320
CAPS = [
    ("01_cab.png", "운전석에서\n실기 코스 그대로", "뒷바퀴 조향 핸들, 전후진·리프트·틸트 레버, 페달"),
    ("02_side.png", "포크 옆 시점으로\n팔레트 꽂기", "드럼 위 팔레트에 끝까지, 20cm 덜 넣으면 실격"),
    ("03_chase.png", "2단 마스트\n2.5t 지게차", "선 밟으면 실격, 포크 50cm 넘으면 실격"),
    ("04_result.png", "상차 45점\n하차 55점 채점표", "실제 배점으로 합격·불합격, 궤적과 실격 지점 표시"),
    ("05_learn.png", "학습 노트와\n코스 도면", "시험 순서·실격 사유·감점 항목·요령"),
    ("06_drills.png", "구간별\n단계 드릴 6종", "출발 준비부터 주차까지 약한 구간만 반복"),
]


def font(size):
    return ImageFont.truetype(os.path.join(ROOT, "fonts", "GowunDodum-Regular.ttf"), size)


def background():
    """어두운 남색 → 검정 대각 그라데이션 + 주황 빛 + 미세 노이즈."""
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    t = (x / W * 0.6 + y / H * 0.4)
    r = 0.07 + 0.03 * (1 - t)
    g = 0.08 + 0.05 * (1 - t)
    b = 0.11 + 0.10 * (1 - t)
    glow = np.exp(-(((x - 420) / 700) ** 2 + ((y - 1100) / 420) ** 2))
    r += glow * 0.55; g += glow * 0.26; b += glow * 0.03
    glow2 = np.exp(-(((x - 2500) / 900) ** 2 + ((y - 150) / 500) ** 2))
    r += glow2 * 0.05; g += glow2 * 0.12; b += glow2 * 0.25
    rng = np.random.default_rng(1)
    n = rng.random((H, W)).astype(np.float32) * 0.03
    rgb = np.stack([r + n, g + n, b + n], axis=-1)
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    for i in range(0, W, 140):  # 가는 대각선 결
        d.line((i, 0, i - 500, H), fill=(255, 255, 255, 8), width=1)
    return img


def shots(src):
    out_dir = os.path.join(ROOT, "store", "screenshots_marketing")
    os.makedirs(out_dir, exist_ok=True)
    bg = background()
    for name, title, sub in CAPS:
        p = os.path.join(src, name)
        if not os.path.exists(p):
            print("skip", name); continue
        im = bg.copy()
        shot = Image.open(p).convert("RGB")
        sw = 1900
        sh = int(shot.height * sw / shot.width)
        shot = shot.resize((sw, sh), Image.LANCZOS)
        x, y = W - sw - 80, (H - sh) // 2
        shadow = Image.new("L", (W, H), 0)
        ImageDraw.Draw(shadow).rounded_rectangle((x + 10, y + 26, x + sw + 10, y + sh + 26), 48, fill=170)
        shadow = shadow.filter(ImageFilter.GaussianBlur(34))
        im.paste((0, 0, 0), (0, 0), shadow)
        mask = Image.new("L", (sw, sh), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh), 44, fill=255)
        im.paste(shot, (x, y), mask)
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((x - 3, y - 3, x + sw + 3, y + sh + 3), 46, outline=(255, 255, 255, 60), width=3)
        tx = 100
        f1, f2 = font(104), font(50)
        lines = title.split("\n")
        ty = H // 2 - (len(lines) * 142 + 130) // 2
        for i, ln in enumerate(lines):
            d.text((tx + 4, ty + i * 142 + 5), ln, font=f1, fill=(0, 0, 0))
            d.text((tx, ty + i * 142), ln, font=f1, fill=(255, 170, 30) if i == 0 else (255, 255, 255))
        sy = ty + len(lines) * 142 + 36
        words, cur, out = sub.split(" "), "", []
        for w in words:
            t = (cur + " " + w).strip()
            if d.textlength(t, font=f2) > x - tx - 60:
                out.append(cur); cur = w
            else:
                cur = t
        out.append(cur)
        for i, ln in enumerate(out):
            d.text((tx + 2, sy + i * 66 + 3), ln, font=f2, fill=(0, 0, 0))
            d.text((tx, sy + i * 66), ln, font=f2, fill=(220, 228, 238))
        im.save(os.path.join(out_dir, name))
        print(name)


def icon(src):
    """지게차 렌더 위에 둥근 배경·문구 없이(애플 규정) 깔끔한 아이콘."""
    p = os.path.join(src, "icon_raw.png")
    if not os.path.exists(p):
        print("skip icon"); return
    raw = Image.open(p).convert("RGB").resize((1024, 1024), Image.LANCZOS)
    # 배경: 주황→진한 주황 방사 그라데이션, 하단 어두운 아스팔트 띠
    y, x = np.mgrid[0:1024, 0:1024].astype(np.float32)
    d2 = np.sqrt(((x - 380) / 900) ** 2 + ((y - 300) / 900) ** 2)
    r = 1.0 - 0.35 * d2; g = 0.62 - 0.30 * d2; b = 0.10 - 0.05 * d2
    bg = Image.fromarray((np.clip(np.stack([r, g, b], -1), 0, 1) * 255).astype(np.uint8))
    # 렌더에서 하늘 대신 배경을 쓰기 위해, 렌더의 밝은 하늘 영역을 마스크로 제거(대략적)
    arr = np.asarray(raw).astype(np.int16)
    sky = (arr[..., 2] > arr[..., 0] + 25) & (arr[..., 2] > 140)
    mask = Image.fromarray(((~sky) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    out = bg.copy()
    out.paste(raw, (0, 0), mask)
    out.save(os.path.join(ROOT, "icon.png"))
    print("icon.png")


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "store", "screenshots", "raw")
    shots(src)
    icon(src)
