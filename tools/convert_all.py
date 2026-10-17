#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批量转换《改道》全部游戏资产：UMD2/UANI → glb

SRC 母版（2026-10-17 修正）：reroute-maker/assets（旧 reroute 目录已不存在）。
- 单位：zerg 三形态 × 5 动画
- 金堆：4 档（metallic 0.65 / roughness 0.8）
- 瓦砾：3 变体（metallic 0.1 / roughness 0.9）
- 矿块：gold_ore（2026-10-17 新建 1b4aea1f，multiview 四视图直出）
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # reroute-godot
SRC = 'D:/G/game/games/reroute-maker/assets'
CONV = os.path.join(ROOT, 'tools', 'umd2_to_gltf.py')
OUT = os.path.join(ROOT, 'assets', 'models')


def zerg(short, uuid, rig):
    base = '%s/model/%s' % (SRC, uuid)
    ann = '%s/Animations/Zerg/%s' % (SRC, short)
    mdl = '%s/Meshes/%s.mdl' % (base, rig)
    anis = ['%s/%s.ani' % (ann, k) for k in ('Idle', 'Crawl', 'Attack', 'Hurt', 'Death')]
    tex_base = '%s/Textures/%s_00' % (base, rig)
    return ('zerg_' + short, mdl, anis, tex_base, 0.0, 0.72)


def static(name, uuid, metallic, roughness):
    base = '%s/model/%s' % (SRC, uuid)
    mdl = '%s/Meshes/%s.mdl' % (base, uuid)
    tex_base = '%s/Textures/%s_00' % (base, uuid)
    return (name, mdl, [], tex_base, metallic, roughness)


JOBS = [
    zerg('worker', '782779429d034d758f4818a2b4e562ee', 'rig-1-a5a3581b-bf1b-40b5-9d49-b4d59aa0a1fd'),
    zerg('blade', 'd42a265bef094bc6bbf3e6bc27a6ccd3', 'rig-1-9e5803a2-abd2-44a3-b846-f9eed44f3cc9'),
    zerg('king', '337f34cfea3841f6a5a438f65a808e45', 'rig-1-e29705ed-0025-4b18-ab20-641876a06efe'),
    static('gold_pile_full', '0653d56b3251449fab458709b4d1d455', 0.65, 0.8),
    static('gold_pile_partial', '0190b2dc503046aa8ba9d1097d575116', 0.65, 0.8),
    static('gold_pile_small', '21ae611243c44e66a9baedc37d52b6e3', 0.65, 0.8),
    static('gold_pile_low', 'bbed72e84d7c4404b88b292f0c52f3d6', 0.65, 0.8),
    static('rubble_sand', '90f2333080c1453582eab7c61ab14e04', 0.1, 0.9),
    static('rubble_brown', 'df4e5ca1f3ac48ddaa05b8b81207cc61', 0.1, 0.9),
    static('rubble_gray', '65e0be7f31a1404ab374761970eea32e', 0.1, 0.9),
    static('gold_ore', '1b4aea1f55fa4fc6b01da6cc34aaada4', 0.15, 0.75),
    # 建筑 3 件（2026-10-17 text2model 直出；spec §12 盒体 fallback 退役）
    static('wall_barrier', 'af89b2b230ed4117aac7875ae3047e16', 0.0, 0.9),
    static('tower_ballista', '110c1cda73f740768820e2f7abc8e5e1', 0.1, 0.85),
    static('core_jade', '2c48fa15f9c74a4bb773f8c06a137867', 0.2, 0.6),
]


def copy_tex(src_path: str) -> str:
    dst = os.path.join(OUT, os.path.basename(src_path))
    if os.path.exists(src_path):
        shutil.copy(src_path, dst)
    return os.path.basename(src_path)


def main() -> int:
    os.makedirs(OUT, exist_ok=True)
    fails = 0
    for (name, mdl, anis, tex_base, met, rgh) in JOBS:
        out = os.path.join(OUT, name + '.glb')
        td = copy_tex(tex_base + '_D.jpg')
        tn = copy_tex(tex_base + '_N.png')
        cmd = [sys.executable, CONV, '--mdl', mdl, '--out', out, '--name', name,
               '--tex-d', td, '--tex-n', tn,
               '--metallic', str(met), '--roughness', str(rgh)]
        for a in anis:
            cmd += ['--ani', a]
        r = subprocess.run(cmd, capture_output=True, text=True)
        line = (r.stdout or r.stderr).strip().splitlines()[-1] if (r.stdout or r.stderr) else '?'
        print(line)
        if r.returncode != 0:
            fails += 1
            print('   STDERR:', (r.stderr or '')[:400])
    print('fails:', fails)
    return 1 if fails else 0


if __name__ == '__main__':
    raise SystemExit(main())
