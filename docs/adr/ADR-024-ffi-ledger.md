# ADR-024 — Bridge FFI 总账校正与机械化

- **Status:** Accepted
- **Date:** 2026-08-03
- **Version:** 1.0
- **新增 Public API:** 0（纯文档 + 脚本 + CI 检查）
- **影响模块:** docs、scripts/ffi-ledger.py、.github/workflows/ci-docs.yml
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

1. **FFI 总账从手抄改为机械生成**：`core/src/bridge.rs` 的 `mod ffi` 是唯一事实
   来源，`scripts/ffi-ledger.py` 统计其 `fn` 声明总数；ADR-024 中的「当前 FFI 面：
   N 项」由 CI-Docs 与脚本输出比对（宪法 Rule 15：文档完整性是机械门禁）。
2. **禁止手抄 FFI 计数**：ADR-001 / ADR-013 / ADR-023 头部的 FFI 计数自此不再
   逐条维护，标注由本 ADR 承接；任何 FFI 增删必须同步运行脚本更新本 ADR。
3. **T-070 起 FFI 面收敛**（ADR-025）：文档生命周期 FFI 统一为 `session_*`
   单一入口；旧 `document_manager_*`（4 项）/ `store_*`（7 项）/ `snapshot_*`
   （5 项）撤销（Rule 14：无生产消费者）。当前 FFI 面：52 项（含 opaque
   类型方法；其中 session_* 21 项为文档生命周期面）。此数字由
   scripts/ffi-ledger.py 机械生成，CI-Docs 校验，勿手改。

## 原因

- 计数漂移是已知失败模式：ADR-013 头部「7 方法」与索引「10 方法 + 1 变体」漂移
  （2026-08-03 经验记录）；T-036 曾校正 experience / audits 计数；手抄必然再次
  漂移（Rule 15 的「不依赖人工记忆」原则）。
- ADR-025 收敛 FFI 面后，总账数字首次可机械定义（bridge.rs ffi mod 的函数声明数），
  校正 + 机械化在同一切片落地，避免再补一次「计数校正」切片。

## 审计

### Single Responsibility

本 ADR 只负责 FFI 总账的一致性与机械化；不改变任何 FFI 语义（语义见 ADR-025）。

### 循环依赖

无（脚本只读 bridge.rs；CI 只读脚本输出与 ADR 文本）。

## 新增 Public API

无。

## 影响模块

- **scripts/ffi-ledger.py**（新增，~25 行，stdlib）：统计 ffi mod 内 `fn` 声明数。
- **.github/workflows/ci-docs.yml**：新增「FFI ledger integrity」步骤（Rule 15
  机械门禁；本地等价 `python3 scripts/ffi-ledger.py` 与本文比对）。
- **docs**：ADR-001 / ADR-013 / ADR-023 头部计数标注由本 ADR 承接。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个 ~25 行脚本 + 1 个 CI 步骤；0 抽象层、0 依赖。
2. **是否永久？** 是——门禁永久有效，但成本恒定且替代手抄（净减人工漂移成本）。
3. **更简单方案？** 继续手抄 = 已知会再次漂移；不做机械校验 = 回到 Rule 15 前
   的「靠自觉」。结论：机械化是最简可靠方案。

结论：1 脚本 / 0 API / 0 抽象层，未触及红线。

## 备注

- 计数口径：`mod ffi` 内 8 空格缩进的 `fn` 声明（含 opaque 类型方法，如
  `Buffer::new` / `BufferId::as_u64`）；不含类型声明（`type X;`）。
- FFI 增删流程：改 bridge.rs → `./bridge/build.sh` → `python3 scripts/ffi-ledger.py`
  更新本 ADR 数字 → CI-Docs 校验。
