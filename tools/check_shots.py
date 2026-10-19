#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""C3 截屏像素校验：尺寸 / 非纯色 / 关键色族（地形暖色、核心青玉、热层红、幽灵绿）。

阈值取自 2026-10-13 实测渲染值（留 2-5 倍余量，防平台微差；真回归=关键色归零必触发）：
  warm=850724  teal=124  red=163694  green=575  diff(game,heat)=0.309  diff(game,ghost)=0.0009
D1-5 追加：game_20x9.png（1600x720，20:9）/ game_narrow.png（960x720，4:3）尺寸+关键色。
D1-5 扩展（2026-10-20）：game_tablet.png（1600x1200，4:3 平板）/ game_16x10.png（1280x800，16:10）尺寸+关键色。
T1 追加：game_closeup.png（改造特写：填两级崖壁+裙脚 / 挖一级坑）尺寸+暖色下限。
跑法：python tools/check_shots.py   （cwd=reroute-godot）
判定：exit 0 + stdout 含 [SHOTS] PASS。
"""
import os
import sys

from PIL import Image

SHOTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'shots')
W, H = 1280, 720

fails = []
checks = 0


def chk(cond, label):
    global checks
    checks += 1
    if not cond:
        fails.append(label)


def load(name):
    p = os.path.join(SHOTS, name)
    if not os.path.exists(p):
        return None
    return Image.open(p).convert('RGB')


def scan(im, pred, step=1):
    """采样统计满足谓词的像素数（关键色用全扫 step=1）。"""
    n = 0
    px = im.load()
    for y in range(0, im.height, step):
        for x in range(0, im.width, step):
            r, g, b = px[x, y]
            if pred(r, g, b):
                n += 1
    return n


def diff_ratio(a, b, step=4):
    if a is None or b is None:
        return 1.0
    px_a, px_b = a.load(), b.load()
    n = d = 0
    for y in range(0, a.height, step):
        for x in range(0, a.width, step):
            n += 1
            ra, ga, ba = px_a[x, y]
            rb, gb, bb = px_b[x, y]
            if abs(ra - rb) + abs(ga - gb) + abs(ba - bb) > 24:
                d += 1
    return d / max(n, 1)


warm = lambda r, g, b: r > 25 and r > b + 5 and g >= b - 2      # 暖石地形
teal = lambda r, g, b: g > r + 25 and b > r + 5 and g > 90      # 核心青玉发光
red = lambda r, g, b: r > 60 and r > g + 25 and r > b + 25      # 热层红带
green = lambda r, g, b: g > r + 40 and g > b + 20 and g > 120   # 幽灵绿板

im_game = load('game.png')
im_heat = load('heat.png')
im_ghost = load('ghost.png')
im_w9 = load('game_20x9.png')
im_narrow = load('game_narrow.png')

for name, im in (('game.png', im_game), ('heat.png', im_heat), ('ghost.png', im_ghost)):
    chk(im is not None, name + ' 存在')
    if im is None:
        continue
    chk(im.size == (W, H), '%s 尺寸 %s != %s' % (name, im.size, (W, H)))
    colors = im.quantize(colors=256).getcolors()
    chk(colors is not None and len(colors) > 60, '%s 唯一色数过少 %d' % (name, len(colors or [])))

if im_game is not None:
    n_warm = scan(im_game, warm)
    n_teal = scan(im_game, teal)
    chk(n_warm > 300000, 'game 暖色地形不足 %d（阈值 300000）' % n_warm)
    chk(n_teal > 60, 'game 核心青玉不足 %d（阈值 60）' % n_teal)
    print('[SHOTS] game warm=%d teal=%d' % (n_warm, n_teal))

if im_heat is not None:
    n_red = scan(im_heat, red)
    chk(n_red > 30000, 'heat 热层红不足 %d（阈值 30000）' % n_red)
    print('[SHOTS] heat red=%d' % n_red)

if im_ghost is not None:
    n_green = scan(im_ghost, green)
    chk(n_green > 200, 'ghost 幽灵绿不足 %d（阈值 200）' % n_green)
    print('[SHOTS] ghost green=%d' % n_green)

# D1-5：宽屏 20:9 与窄屏 4:3（阈值保守，目视件为主）
for name, im, dims in (('game_20x9.png', im_w9, (1600, 720)), ('game_narrow.png', im_narrow, (960, 720))):
    chk(im is not None, name + ' 存在')
    if im is None:
        continue
    chk(im.size == dims, '%s 尺寸 %s != %s' % (name, im.size, dims))
    colors2 = im.quantize(colors=256).getcolors()
    chk(colors2 is not None and len(colors2) > 60, '%s 唯一色数过少 %d' % (name, len(colors2 or [])))
    n_warm2 = scan(im, warm)
    n_teal2 = scan(im, teal)
    chk(n_warm2 > 250000, '%s 暖色地形不足 %d（阈值 250000）' % (name, n_warm2))
    chk(n_teal2 > 30, '%s 核心青玉不足 %d（阈值 30）' % (name, n_teal2))
    print('[SHOTS] %s warm=%d teal=%d' % (name, n_warm2, n_teal2))

# D1-5 扩展：平板 4:3（1600x1200）与 16:10（1280x800）
im_tablet = load('game_tablet.png')
im_16x10 = load('game_16x10.png')
for name, im, dims in (('game_tablet.png', im_tablet, (1600, 1200)), ('game_16x10.png', im_16x10, (1280, 800))):
    chk(im is not None, name + ' 存在')
    if im is None:
        continue
    chk(im.size == dims, '%s 尺寸 %s != %s' % (name, im.size, dims))
    colors4 = im.quantize(colors=256).getcolors()
    chk(colors4 is not None and len(colors4) > 60, '%s 唯一色数过少 %d' % (name, len(colors4 or [])))
    n_warm4 = scan(im, warm)
    n_teal4 = scan(im, teal)
    chk(n_warm4 > 250000, '%s 暖色地形不足 %d（阈值 250000）' % (name, n_warm4))
    chk(n_teal4 > 30, '%s 核心青玉不足 %d（阈值 30）' % (name, n_teal4))
    print('[SHOTS] %s warm=%d teal=%d' % (name, n_warm4, n_teal4))

if im_game is not None and im_heat is not None:
    d1 = diff_ratio(im_game, im_heat)
    chk(d1 > 0.05, 'game 与 heat 差异不足 %.4f（阈值 0.05）' % d1)
    print('[SHOTS] diff game-heat=%.4f' % d1)
if im_game is not None and im_ghost is not None:
    d2 = diff_ratio(im_game, im_ghost)
    # 2026-10-17 地面三平面纹理落地后 AA 边缘差实测 0.00030（原 0.0004，阈值 0.0003 零余量失灵）；
    # 校准为 0.0001（真回归=ghost 截图与 game 完全相同 → d2≈0，仍被钳住；下方 green>200 为强信号）
    chk(d2 > 0.0001, 'game 与 ghost 差异不足 %.5f（阈值 0.0001）' % d2)
    print('[SHOTS] diff game-ghost=%.5f' % d2)

# 自然化 T1：改造特写（填两级崖壁+裙脚 / 挖一级坑）；阈值保守（近景构图，真回归=空帧/纯色）
im_close = load('game_closeup.png')
chk(im_close is not None, 'game_closeup.png 存在')
if im_close is not None:
    chk(im_close.size == (W, H), 'game_closeup 尺寸 %s != %s' % (im_close.size, (W, H)))
    colors3 = im_close.quantize(colors=256).getcolors()
    chk(colors3 is not None and len(colors3) > 60, 'game_closeup 唯一色数过少 %d' % (len(colors3 or [])))
    n_warm3 = scan(im_close, warm)
    chk(n_warm3 > 300000, 'game_closeup 暖色地形不足 %d（阈值 300000）' % n_warm3)
    print('[SHOTS] game_closeup warm=%d' % n_warm3)

print('[SHOTS] checks=%d fail=%d' % (checks, len(fails)))
for f in fails:
    print('[SHOTS] FAIL:', f)
print('[SHOTS]', 'PASS' if not fails else 'FAIL')
sys.exit(0 if not fails else 1)
