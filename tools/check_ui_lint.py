#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""UI 守规 lint（v2.2 维护方案①：样式工厂 ui_style.gd 为唯一构造口）。

守规三条（checker 逐条扫 game/*.gd）：
  L1  裸 Color8/Color 构造：只允许 hud.gd 的 DARK 调色板定义区与 ui_style.gd 全文
      （screens.gd 零白名单——一切结构常量必须进工厂）。
  L2  StyleBoxFlat.new / Theme.new 直接构造：只允许 ui_style.gd（工厂本体）与
      hud.gd 既有探针面例外清单（超出清单 = 红）。Label/Button 等 Control 构造不受限。
  L3  theme_type_variation 字符串必须引用 UiStyle.* 常量（禁止字面量硬编码变体名）。

跑法：python tools/check_ui_lint.py   （cwd=reroute-godot）
判定：exit 0 + stdout 含 [UI-LINT] PASS；违规行 [UI-LINT] FAIL + 文件:行。
"""
import re
import os
import sys

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'game')

# L3（变体名）先行的正则
RE_DARK_START = re.compile(r'^\s*var DARK\s*:?=')
VARIATION_LIT = re.compile(r'theme_type_variation\s*=\s*"')
RE_COLOR8 = re.compile(r'(^|[^.\w])Color8\(')
RE_COLOR = re.compile(r'(^|[^.\w])Color\(')
# 合法豁免：从已具名 token 重组透明度（纯算术，无新常量）
RE_TOKEN_REMIX = re.compile(r'Color\(DARK\[')


def dark_zone(lines):
    """L1 白名单 = `var DARK := {` 起至第一个 `}` 止（调色板定义区）。"""
    s = e = -1
    for i, ln in enumerate(lines):
        if RE_DARK_START.match(ln):
            s = i + 1
        elif s > 0 and ln.rstrip() == '}':
            e = i + 1
            break
    return (s, e) if s > 0 and e > s else (1, 0)


def fail_lines():
    fails = []

    def read(path):
        with open(os.path.join(ROOT, path), encoding='utf-8') as f:
            return [ln.split('#', 1)[0] for ln in f.read().splitlines()]  # 扫描剥注释

    # L1：裸 Color 构造，白名单=ui_style.gd 全文 + hud.gd 的 DARK 区
    for fname in ('hud.gd', 'screens.gd', 'main.gd', 'view.gd', 'ui_style.gd'):
        lines = read(fname)
        zone = (1, 10 ** 6) if fname == 'ui_style.gd' else dark_zone(lines) if fname == 'hud.gd' else (1, 0)
        for i, ln in enumerate(lines, 1):
            raw8 = RE_COLOR8.search(ln)
            rawc = (not raw8) and RE_COLOR.search(ln)
            if not (raw8 or rawc):
                continue
            if not any(zone[0] <= i <= zone[1] for _ in (0,)):
                msg = 'L1 裸 Color8 越区' if raw8 else 'L1 色 token 越区（应走 UiStyle/加白名单）'
                if rawc and RE_TOKEN_REMIX.search(ln):
                    continue  # token 透明度重组豁免
                fails.append(f'{fname}:{i} {msg} → {ln.strip()}')

    # L2：直接构造样式/纹理对象（工厂口唯一）
    for fname in ('hud.gd', 'screens.gd', 'main.gd', 'view.gd'):
        lines = read(fname)
        for i, ln in enumerate(lines, 1):
            for pat in ('StyleBoxFlat.new', 'Theme.new', 'GradientTexture2D.new', 'NoiseTexture2D.new', 'Gradient.new'):
                if pat in ln:
                    fails.append(f'{fname}:{i} L2 违规 {pat}（应走 UiStyle 工厂）→ {ln.strip()}')

    # L3
    for fname in ('hud.gd', 'screens.gd', 'main.gd', 'view.gd'):
        lines = read(fname)
        for i, ln in enumerate(lines, 1):
            if VARIATION_LIT.search(ln):
                fails.append(f'{fname}:{i} L3 字面量变体名（应引用 UiStyle.* 常量）→ {ln.strip()}')

    return fails


def main():
    fails = fail_lines()
    n = 0
    print(f'[UI-LINT] scanned game/*.gd (L1 色常量区/ L2 工厂构造口/ L3 变体名守规)')
    if fails:
        for f in fails:
            print('[UI-LINT] FAIL', f)
            n += 1
        print('[UI-LINT] checks=3 fail={0}'.format(n))
        print('[UI-LINT] FAIL')
        return 1
    print('[UI-LINT] checks=3 fail=0')
    print('[UI-LINT] PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
