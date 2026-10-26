#!/usr/bin/env python3
"""跑闸外壳：运行 Godot 命令并扫描输出，出现引擎错误即判红。

背景：GDScript 测试夹具只能统计断言失败，看不到引擎打印的 SCRIPT ERROR，
于是「断言 0 失败 + 运行时报错」会被误判为通过（假绿）。本工具不改探针，
只在最外层看日志：只要出现 SCRIPT ERROR / ERROR: 就返回非零。

用法（cwd=项目根）：
  python tools/gate_run.py --headless -s res://tests/run_tests.gd
  python tools/gate_run.py --scan-file logs/xxx.log   # 只复检已有日志
  python tools/gate_run.py --allow "已知无害报错" --headless -s res://...

参数：--exe 指定 Godot 可执行文件；--project 指定项目路径（默认当前目录）；
--require 指定输出中必须出现的成功标记（默认 PASS）。
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

DEFAULT_EXE = (
    r"d:\G\game\Godot_v4.7.2-stable_mono_win64"
    r"\Godot_v4.7.2-stable_mono_win64_console.exe"
)
BAD_PATTERNS = ("SCRIPT ERROR", "ERROR:")


def judge(text: str, allow: list[str], require: str) -> tuple[int, list[str]]:
    """返回 (退出码, 命中的错误行)。白名单按子串过滤，避免已知无害告警误杀。"""
    hits = []
    for line in text.splitlines():
        if any(p in line for p in BAD_PATTERNS):
            if any(a and a in line for a in allow):
                continue
            hits.append(line.strip())
    if hits:
        return 1, hits
    if require and require not in text:
        return 1, [f"未出现成功标记：{require}"]
    return 0, []


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--exe", default=DEFAULT_EXE)
    ap.add_argument("--project", default=os.getcwd())
    ap.add_argument("--scan-file", default="")
    ap.add_argument("--require", default="PASS")
    ap.add_argument("--allow", action="append", default=[])
    # 工具只认自己的参数，其余原样透传给 Godot（如 --headless / -s）
    args, godot_args = ap.parse_known_args()

    if args.scan_file:
        with open(args.scan_file, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    else:
        cmd = [args.exe, "--path", args.project, *godot_args]
        proc = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
        text = proc.stdout + "\n" + proc.stderr
        print(text, end="" if text.endswith("\n") else "\n")
        if proc.returncode != 0:
            print(f"[GATE] 进程退出码 {proc.returncode}", file=sys.stderr)
            return proc.returncode

    code, hits = judge(text, args.allow, args.require)
    if code:
        print(f"[GATE] RED：{len(hits)} 处错误")
        for h in hits[:10]:
            print("  " + h)
    else:
        print("[GATE] GREEN")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
