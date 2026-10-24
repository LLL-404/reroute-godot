#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""UI 守规 lint（v2.2 维护方案①：样式工厂 ui_style.gd 为唯一构造口）。

守规四条（checker 逐条扫 game/*.gd 与 game/**/*.tscn）：
  L1  裸 Color8/Color 构造：只允许 hud.gd 的 DARK 调色板定义区与 ui_style.gd 全文
      （screens.gd 零白名单——一切结构常量必须进工厂）。
  L2  StyleBoxFlat.new / Theme.new 直接构造：只允许 ui_style.gd（工厂本体）与
      hud.gd 既有探针面例外清单（超出清单 = 红）。Label/Button 等 Control 构造不受限。
  L3  theme_type_variation 字符串必须引用 UiStyle.* 常量（禁止字面量硬编码变体名）。
  L4  .tscn 只承载结构：禁止样式资源、theme 覆盖与 S 相关尺寸（否则绕过工厂与缩放）。

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

# 扫描对象（相对 ROOT 的路径，按整理后的四层目录 app/core/view/ui 定位）
SCAN_L1 = ('ui/hud.gd', 'ui/screens.gd', 'app/main.gd', 'view/view.gd', 'ui/ui_style.gd')
SCAN_STYLE = ('ui/hud.gd', 'ui/screens.gd', 'app/main.gd', 'view/view.gd')

# L3（变体名）先行的正则
RE_DARK_START = re.compile(r'^\s*var DARK\s*:?=')
VARIATION_LIT = re.compile(r'theme_type_variation\s*=\s*"')
RE_COLOR8 = re.compile(r'(^|[^.\w])Color8\(')
RE_COLOR = re.compile(r'(^|[^.\w])Color\(')
# 合法豁免：从已具名 token 重组透明度（纯算术，无新常量；DARK 调色板与 C 主题色板同源）
RE_TOKEN_REMIX = re.compile(r'Color\((?:DARK|C)\[')

# L4：.tscn 只允许结构节点；以下 token 一旦出现即说明样式/尺寸绕过了工厂与 S 口径
TSCN_BANNED = (
    'StyleBoxFlat',
    'type="Theme"',
    'GradientTexture2D',
    'NoiseTexture2D',
    'ShaderMaterial',
    'theme_type_variation',
    'theme_override_',
    'custom_minimum_size',
)
RE_THEME_ASSIGN = re.compile(r'^\s*theme\s*=\s*\S')


def tscn_fail_lines():
    """扫描 game/**/*.tscn，返回违规行清单（L4）。"""
    fails = []
    proj = os.path.join(ROOT, '..')
    for base, _dirs, files in os.walk(ROOT):
        for fname in sorted(files):
            if not fname.endswith('.tscn'):
                continue
            path = os.path.join(base, fname)
            rel = os.path.relpath(path, proj).replace('\\', '/')
            with open(path, encoding='utf-8') as f:
                for i, ln in enumerate(f.read().splitlines(), 1):
                    hits = [t for t in TSCN_BANNED if t in ln]
                    if hits or RE_THEME_ASSIGN.match(ln):
                        tag = ' '.join(hits) if hits else 'theme 赋值'
                        fails.append(f'{rel}:{i} L4 场景承载样式/尺寸（{tag}）→ {ln.strip()}')
    return fails


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
    for fname in SCAN_L1:
        lines = read(fname)
        zone = (1, 10 ** 6) if fname == 'ui/ui_style.gd' else dark_zone(lines) if fname == 'ui/hud.gd' else (1, 0)
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
    for fname in SCAN_STYLE:
        lines = read(fname)
        for i, ln in enumerate(lines, 1):
            for pat in ('StyleBoxFlat.new', 'Theme.new', 'GradientTexture2D.new', 'NoiseTexture2D.new', 'Gradient.new'):
                if pat in ln:
                    fails.append(f'{fname}:{i} L2 违规 {pat}（应走 UiStyle 工厂）→ {ln.strip()}')

    # L3
    for fname in SCAN_STYLE:
        lines = read(fname)
        for i, ln in enumerate(lines, 1):
            if VARIATION_LIT.search(ln):
                fails.append(f'{fname}:{i} L3 字面量变体名（应引用 UiStyle.* 常量）→ {ln.strip()}')

    # L4：.tscn 结构守规
    fails.extend(tscn_fail_lines())

    return fails


def main():
    fails = fail_lines()
    n = 0
    print(f'[UI-LINT] scanned game/{", game/".join(SCAN_L1)} 与 game/**/*.tscn (L1 色常量区/ L2 工厂构造口/ L3 变体名/ L4 场景守规)')
    if fails:
        for f in fails:
            print('[UI-LINT] FAIL', f)
            n += 1
        print('[UI-LINT] checks=4 fail={0}'.format(n))
        print('[UI-LINT] FAIL')
        return 1
    print('[UI-LINT] checks=4 fail=0')
    print('[UI-LINT] PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
