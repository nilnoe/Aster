#!/usr/bin/env python3
"""T-062 变异测试工具：自动注入 / 恢复 / 结果记录（T-051 手工流程脚本化）。

决策依据：
- 变异测试定位测试盲区的原理（ADR-022 / docs/testing.md「测试方法论强化」）：
  向实现注入「常见错误变体」并跑目标测试，变体全绿 = 该路径无测试保护。
  T-051 起该流程是每切片质量门禁的组成部分（新增状态机逻辑先变异）。
- 只用标准库（Rule 7：subprocess / json / pathlib 足够；不引第三方）。
- 恢复保证：每个变异点注入前先在内存备份整文件，跑完立即还原；old 必须
  唯一匹配（不唯一 = 变异点漂移，跳过并计失败，防止注入错位置）。
- M6（挂起变体）不可自动化（会阻塞进程），清单已注明不纳入。

用法：
    python3 scripts/mutate.py                 # 跑清单全部变异点
    python3 scripts/mutate.py --only M1       # 只跑指定变异点
退出码：0 = 全部变异点按预期被捕获/存活；1 = 有变异点漂移或测试预期不符。
"""

import json
import subprocess
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT = SCRIPT_DIR.parent
CATALOG = SCRIPT_DIR / "mutations.json"


def main() -> int:
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    failed: list[str] = []

    for entry in catalog["mutations"]:
        if only and entry["id"] != only:
            continue
        target = ROOT / entry["file"]
        original = target.read_text(encoding="utf-8")
        matches = original.count(entry["old"])
        if matches != 1:
            # 变异点漂移：清单与源码不一致，注入错位置比不注入更危险。
            print(f"[SKIP] {entry['id']} {entry['label']}: 变异点匹配 {matches} 次（须恰为 1）")
            failed.append(entry["id"])
            continue

        target.write_text(original.replace(entry["old"], entry["new"]), encoding="utf-8")
        started = time.monotonic()
        try:
            run = entry["run"]
            proc = subprocess.run(
                run["cmd"],
                cwd=ROOT / run["cwd"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=600,
            )
            caught = proc.returncode != 0
        finally:
            target.write_text(original, encoding="utf-8")
        elapsed = time.monotonic() - started

        expect_caught = entry["expected"] == "caught"
        ok = caught == expect_caught
        status = "CAUGHT" if caught else "SURVIVED"
        mark = "ok" if ok else "FAIL"
        print(
            f"[{mark}] {entry['id']} {entry['label']}: {status} "
            f"(预期 {'caught' if expect_caught else 'survives'}) {elapsed:.1f}s"
        )
        if not ok:
            failed.append(entry["id"])

    if failed:
        print(f"变异门禁未通过：{', '.join(failed)}")
        return 1
    print("变异门禁通过：全部变异点按预期被捕获（无盲区存活）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
