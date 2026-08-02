#!/usr/bin/env python3
"""criterion 基准回归告警（T-033，ADR-021 v1.1）。

用法：
  本地生成基线（先 `cd core && cargo bench`）并提交：
    python3 scripts/bench-regression.py --save-baseline bench-baseline \
      --criterion-root core/target/criterion
  CI / 本地对比（先 `cd core && cargo bench -- --quick`）：
    python3 scripts/bench-regression.py --baseline-dir bench-baseline \
      --criterion-root core/target/criterion [--threshold 0.10]

规则（ADR-021 v1.1）：
- 只比较 mean.point_estimate（纳秒）；当前 > 基线 × (1 + threshold) 视为回归，
  exit 1；改进与持平不影响门禁。
- 基线均值 < 10µs 的项跳过（超快基准跨机器噪声占比大，比较无意义）。
- 仅用 Python 标准库（Rule 11：macOS / GitHub Actions 自带 python3，不引依赖）。
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

MEAN_NS_FLOOR = 100_000  # 100µs（T-048）：共享 runner 的 quick 模式噪声可达
# 数十 µs，10µs 下限仍会被噪声触发；低于 100µs 的基准跳过（跨机器噪声不可比）。


def collect_results(criterion_root: Path) -> dict[str, float]:
    """扫描 `<criterion>/<bench>/<sample>/new/estimates.json` → {相对路径: mean 纳秒}。"""
    results: dict[str, float] = {}
    for est in criterion_root.rglob("new/estimates.json"):
        rel = est.parent.parent.relative_to(criterion_root)
        data = json.loads(est.read_text(encoding="utf-8"))
        results[str(rel)] = float(data["mean"]["point_estimate"])
    return results


def save_baseline(criterion_root: Path, baseline_dir: Path) -> int:
    results = collect_results(criterion_root)
    if not results:
        print("未找到 criterion 结果（先运行 cargo bench）", file=sys.stderr)
        return 1
    for rel in sorted(results):
        src = criterion_root / rel / "new" / "estimates.json"
        dst = baseline_dir / rel / "estimates.json"
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    print(f"基线已保存：{len(results)} 项 → {baseline_dir}/")
    return 0


def compare(criterion_root: Path, baseline_dir: Path, threshold: float) -> int:
    current = collect_results(criterion_root)
    if not current:
        print("未找到 criterion 结果（先运行 cargo bench）", file=sys.stderr)
        return 1
    regressed: list[str] = []
    compared = 0
    skipped = 0
    missing = 0
    for rel, cur_ns in sorted(current.items()):
        base_file = baseline_dir / rel / "estimates.json"
        if not base_file.exists():
            missing += 1
            print(f"  无基线（新基准，跳过）：{rel}")
            continue
        base_ns = float(json.loads(base_file.read_text(encoding="utf-8"))["mean"]["point_estimate"])
        if base_ns < MEAN_NS_FLOOR:
            skipped += 1
            continue
        compared += 1
        delta_pct = (cur_ns / base_ns - 1) * 100
        if delta_pct > threshold * 100:
            state = "REGRESSED"
            regressed.append(rel)
        elif delta_pct < 0:
            state = "improved"
        else:
            state = "ok"
        print(
            f"  {state:>9} {delta_pct:+6.1f}%  {rel}  "
            f"({base_ns / 1e6:.4f}ms → {cur_ns / 1e6:.4f}ms)"
        )
    print(
        f"对比完成：{compared} 项参与，{skipped} 项低于 10µs 跳过，{missing} 项无基线；"
        f"回归 {len(regressed)} 项（阈值 {threshold:.0%}）"
    )
    if regressed:
        print("回归基准：" + ", ".join(regressed), file=sys.stderr)
        return 1
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="criterion 基准回归告警（T-033，ADR-021 v1.1）")
    parser.add_argument("--save-baseline", metavar="DIR", help="把当前 cargo bench 结果保存为基线目录")
    parser.add_argument("--baseline-dir", default="bench-baseline", metavar="DIR", help="基线目录")
    parser.add_argument("--threshold", type=float, default=0.10, help="回归阈值（默认 0.10 = 10%%）")
    parser.add_argument("--criterion-root", default="target/criterion", help="criterion 结果根目录")
    args = parser.parse_args()
    root = Path(args.criterion_root)
    if not root.exists():
        print(f"criterion 结果目录不存在：{root}（先运行 cargo bench）", file=sys.stderr)
        return 1
    if args.save_baseline:
        return save_baseline(root, Path(args.save_baseline))
    return compare(root, Path(args.baseline_dir), args.threshold)


if __name__ == "__main__":
    sys.exit(main())
