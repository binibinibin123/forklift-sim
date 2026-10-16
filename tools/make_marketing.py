"""스토어 스크린샷: 배경(store/codex/bg.png) + 실제 화면 + 왼쪽 문구 → store/screenshots_marketing/ (2868x1320)."""
import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 2868, 1320
CAPS = [
    ("01_cab.png", "운전석에서 보는\n실기 코스", "포크 높이·틸트를 보며 팔레트 상차"),
    ("02_side.png", "포크 옆 시점으로\n구멍 맞추기", "드럼 위 팔레트에 끝까지 꽂기"),
    ("03_top.png", "실기 시험 순서\n그대로", "상차 → 전진 → 하역 → 후진선 → 후진 → 주차"),
    ("04_chase.png", "뒷바퀴 조향\n지게차 감각", "핸들·전후진·리프트·틸트 레버와 페달"),
    ("05_result.png", "실격·감점\n자동 채점", "선 접촉, 포크 50cm, 4분 초과까지 확인"),
    ("06_menu.png", "연습 모드는\n하역까지 무료", "1회 해제로 모의시험·리플레이"),
]


def font(size):
    return ImageFont.truetype(os.path.join(ROOT, "fonts", "GowunDodum-Regular.ttf"), size)


def main():
    bg_path = os.path.join(ROOT, "store", "codex", "bg.png")
    out_dir = os.path.join(ROOT, "store", "screenshots_marketing")
    os.makedirs(out_dir, exist_ok=True)
    bg = Image.open(bg_path).convert("RGB")
    # cover-fit
    s = max(W / bg.width, H / bg.height)
    bg = bg.resize((int(bg.width * s) + 1, int(bg.height * s) + 1), Image.LANCZOS)
    bg = bg.crop(((bg.width - W) // 2, (bg.height - H) // 2, (bg.width - W) // 2 + W, (bg.height - H) // 2 + H))
    for name, title, sub in CAPS:
        im = bg.copy()
        shot = Image.open(os.path.join(ROOT, "store", "screenshots", name)).convert("RGB")
        sw = 1880
        sh = int(shot.height * sw / shot.width)
        shot = shot.resize((sw, sh), Image.LANCZOS)
        x, y = W - sw - 90, (H - sh) // 2
        # 그림자
        shadow = Image.new("L", (W, H), 0)
        ImageDraw.Draw(shadow).rounded_rectangle((x + 10, y + 24, x + sw + 10, y + sh + 24), 48, fill=150)
        shadow = shadow.filter(ImageFilter.GaussianBlur(30))
        im.paste((0, 0, 0), (0, 0), shadow)
        mask = Image.new("L", (sw, sh), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw, sh), 44, fill=255)
        im.paste(shot, (x, y), mask)
        d = ImageDraw.Draw(im)
        # 왼쪽 글 영역 살짝 어둡게
        tx = 110
        f1, f2 = font(108), font(54)
        lines = title.split("\n")
        ty = H // 2 - (len(lines) * 150 + 120) // 2
        for i, ln in enumerate(lines):
            d.text((tx + 4, ty + i * 150 + 5), ln, font=f1, fill=(0, 0, 0))
            d.text((tx, ty + i * 150), ln, font=f1, fill=(255, 196, 40) if i == 0 else (255, 255, 255))
        sy = ty + len(lines) * 150 + 40
        words, cur, out = sub.split(" "), "", []
        for w in words:
            t = (cur + " " + w).strip()
            if d.textlength(t, font=f2) > x - tx - 60:
                out.append(cur)
                cur = w
            else:
                cur = t
        out.append(cur)
        for i, ln in enumerate(out):
            d.text((tx + 2, sy + i * 70 + 3), ln, font=f2, fill=(0, 0, 0))
            d.text((tx, sy + i * 70), ln, font=f2, fill=(225, 232, 240))
        im.save(os.path.join(out_dir, name))
        print(name)


if __name__ == "__main__":
    main()
