#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""C3 截屏像素校验：尺寸 / 非纯色 / 关键色族（地形暖色、核心青玉、热层红、幽灵绿）。

阈值取自 2026-10-13 实测渲染值（留 2-5 倍余量，防平台微差；真回归=关键色归零必触发）：
  warm=850724  teal=124  red=163694  green=575  diff(game,heat)=0.309  diff(game,ghost)=0.0009
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

if im_game is not None and im_heat is not None:
    d1 = diff_ratio(im_game, im_heat)
    chk(d1 > 0.05, 'game 与 heat 差异不足 %.4f（阈值 0.05）' % d1)
    print('[SHOTS] diff game-heat=%.4f' % d1)
if im_game is not None and im_ghost is not None:
    d2 = diff_ratio(im_game, im_ghost)
    chk(d2 > 0.0003, 'game 与 ghost 差异不足 %.5f（阈值 0.0003）' % d2)
    print('[SHOTS] diff game-ghost=%.5f' % d2)

print('[SHOTS] checks=%d fail=%d' % (checks, len(fails)))
for f in fails:
    print('[SHOTS] FAIL:', f)
print('[SHOTS]', 'PASS' if not fails else 'FAIL')
sys.exit(0 if not fails else 1)
