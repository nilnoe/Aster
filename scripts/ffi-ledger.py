#!/usr/bin/env python3
"""FFI 总账机械生成（ADR-024，宪法 Rule 15）。

决策依据：FFI 计数此前手抄进 ADR 头部，ADR-013 头部与索引漂移（ADR-024 提议）
即手抄代价；本脚本以 core/src/bridge.rs 的 `mod ffi` 为唯一事实来源统计 fn 声明
数，CI-Docs 用它比对 ADR-024 的「当前 FFI 面：N 项」，漂移即红（Rule 15：
文档完整性是机械门禁，不依赖人工记忆）。只用标准库（Rule 7）。

用法：python3 scripts/ffi-ledger.py   # 输出当前 FFI 函数总数
"""

import re
import sys
from pathlib import Path

BRIDGE = Path(__file__).resolve().parents[1] / "core" / "src" / "bridge.rs"


def count_ffi_fns() -> int:
    """统计 `mod ffi` 内 8 空格缩进的 `fn` 声明（含 opaque 类型方法）。"""
    src = BRIDGE.read_text(encoding="utf-8")
    body = src.split("mod ffi {", 1)[1].split("}", 1)[0]
    return len(re.findall(r"(?m)^        fn ", body))


if __name__ == "__main__":
    print(count_ffi_fns())
    sys.exit(0)
