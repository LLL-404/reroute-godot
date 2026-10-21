# -*- coding: utf-8 -*-
"""生成 TapTap 商店素材：banner/logo/cover/cover_vertical/library_hero + 截图副本"""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

ROOT = r"D:\G\game\games\reroute-godot"
SRC = os.path.join(ROOT, "shots", "store", "store_header.png")
OUT = os.path.join(ROOT, "shots", "submit")
os.makedirs(OUT, exist_ok=True)

art = Image.open(SRC).convert("RGB")   # 1920x1080
W, H = art.size

# ---------- banner_4: 16:9 1920x1080, JPEG <4MB ----------
art.save(os.path.join(OUT, "banner_4.jpg"), "JPEG", quality=92, optimize=True)

# ---------- library_hero: 3840x1240, 禁止文字 ----------
# 从 1920x1080 取 1920x620 横带（围绕水晶 y=120..740），再 2x 放大
band = art.crop((0, 120, 1920, 740))          # 1920x620
band = band.resize((3840, 1240), Image.LANCZOS)
band.save(os.path.join(OUT, "library_hero.jpg"), "JPEG", quality=90, optimize=True)

# ---------- logo 1280x720 透明 ----------
def make_logo(size, font_path, title="改道", sub="REROUTE"):
    lw, lh = size
    logo = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
    d = ImageDraw.Draw(logo)
    ft = ImageFont.truetype(font_path, int(lh * 0.46))
    fs = ImageFont.truetype(font_path, int(lh * 0.075))
    # 标题居中偏上
    bbox = d.textbbox((0, 0), title, font=ft)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    tx, ty = (lw - tw) / 2, lh * 0.16
    # 阴影
    for dx, dy in [(3, 5), (-3, 5), (3, -5), (-3, -5)]:
        d.text((tx + dx - bbox[0], ty + dy - bbox[1]), title, font=ft, fill=(20, 12, 6, 190))
    d.text((tx - bbox[0], ty - bbox[1]), title, font=ft, fill=(242, 212, 138, 255))
    # 副标
    sb = d.textbbox((0, 0), sub, font=fs)
    sw = sb[2] - sb[0]
    sx, sy = (lw - sw) / 2, lh * 0.72
    d.text((sx - sb[0], sy - sb[1]), sub, font=fs, fill=(242, 212, 138, 230))
    # 下划线
    line_w = int(sw * 1.6)
    d.line([(lw - line_w) / 2, lh * 0.86, (lw + line_w) / 2, lh * 0.86],
           fill=(242, 212, 138, 200), width=max(2, int(lh * 0.004)))
    return logo

FONT = os.path.join(ROOT, "assets", "fonts", "NotoSerifSC-Bold-Sub.ttf")
logo = make_logo((1280, 720), FONT)
logo.save(os.path.join(OUT, "logo.png"))
print("logo glyph test ok")

# ---------- cover 920x430 (460:215) 含 Logo ----------
cw, ch = 920, 430
# 原图 1920x1080 -> 目标 2.1395:1，需裁 1920x897（居中略偏下，保水晶）
crop_h = int(W / (cw / ch))
top = max(0, min(H - crop_h, int(H * 0.36)))
cover = art.crop((0, top, W, top + crop_h)).resize((cw, ch), Image.LANCZOS)
lg = logo.resize((int(cw * 0.42), int(cw * 0.42 * 720 / 1280)), Image.LANCZOS)
cover = cover.convert("RGBA")
cover.alpha_composite(lg, (int(cw * 0.04), int(ch * 0.06)))
cover.convert("RGB").save(os.path.join(OUT, "cover.jpg"), "JPEG", quality=92, optimize=True)

# ---------- cover_vertical 1200x1800 (2:3) 含 Logo ----------
vw, vh = 1200, 1800
crop_w = int(H * vw / vh)          # 1080*2/3=720
left = (W - crop_w) // 2
cv = art.crop((left, 0, left + crop_w, H)).resize((vw, vh), Image.LANCZOS)
lg2 = logo.resize((int(vw * 0.62), int(vw * 0.62 * 720 / 1280)), Image.LANCZOS)
cv = cv.convert("RGBA")
cv.alpha_composite(lg2, (int(vw * 0.19), int(vh * 0.07)))
cv.convert("RGB").save(os.path.join(OUT, "cover_vertical.jpg"), "JPEG", quality=92, optimize=True)

# ---------- 截图副本（真实游戏画面，1280x720） ----------
for name in ["game", "heat", "ghost", "smoke_mid", "game_closeup"]:
    src = os.path.join(ROOT, "shots", name + ".png")
    im = Image.open(src).convert("RGB")
    if im.size != (1280, 720):
        im = im.resize((1280, 720), Image.LANCZOS)
    im.save(os.path.join(OUT, f"shot_{name}.png"), "PNG", optimize=True)

for f in sorted(os.listdir(OUT)):
    p = os.path.join(OUT, f)
    im = Image.open(p)
    print(f"{os.path.getsize(p)/1048576:7.2f}MB  {im.size[0]}x{im.size[1]}  {im.mode:5s}  {f}")
