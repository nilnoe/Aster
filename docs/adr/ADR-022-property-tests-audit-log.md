# ADR-022 — 属性测试（proptest）与审计记录制度

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 0（dev-dependency + 测试 + 文档制度）
- **影响模块:** core（dev-dependencies、tests/property.rs）、docs/testing.md、
  docs/audits.md（新增）、WORKFLOW（Audit 步骤）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

1. **属性测试用 proptest**（dev-dependency）：生成任意输入验证不变量，覆盖手写用例
   无法穷举的边界（UTF-8 非边界偏移、任意操作序列、undo/redo 往返）。
2. **第一波属性测试范围**（`core/tests/property.rs`）：
   - Buffer：任意文本 + 任意字节偏移上的 insert / delete——合法边界必须成功且保持
     UTF-8 安全、非法边界必须失败且不改变文本；delete 后原位 insert 被删内容 =
     原文（round-trip）。
   - Editor：type_text / delete_backward / 光标移动与朴素模型差分（文本 + 光标逐
     步一致）；任意操作序列后 undo 全部 → 空文本，再 redo 全部 → 原快照。
   - Layout：任意文本行结构不变量——行数 == `split('\n')` 行数、行起点有序且首
     行为 0、每个字节偏移落在其所属行的 `[start, end]` 内、行内文本不含 `\n`。
3. **审计记录制度**：新增 `docs/audits.md`，每个切片在 Architecture Audit 后追加
   一行（切片、Commit、审计项、结论、违规与处置）；WORKFLOW Audit 步骤要求"审计
   结论必须落表，无记录的审计视为未执行"。
4. **CI**：属性测试随 `cargo test` 运行；策略规模保持小（≤8 字符文本、≤60 步
   操作序列），用例数用 proptest 默认值（可经 `PROPTEST_CASES` 调整），不引入
   `attr-macro` 特性（避免额外 proc-macro 依赖，Rule 9）。

## 原因

- **为什么标准库不能解决（Rule 7）**：std 无属性测试框架；手写随机 + 断言不具备
   shrinking（最小化失败用例）与可复现种子，调试成本高。proptest 是 Rust 属性测试
  事实标准（Rule 11 复用优先）。
- **为什么现在做**：docs/testing.md 的「工具（计划）」早已承诺 proptest 但从未落地
  （计划空转，同 ADR-004 教训，Rule 13）；当前 108 个测试全部为手写契约用例，
  边界覆盖靠人肉枚举。
- **为什么审计要留痕**：审计此前是 WORKFLOW 中的口头步骤、无产物——ADR-018 索引
  漏登、ADR-004 失约、零消费者模块交付均通过 audit 未被拦下；不可追溯的审计等于
  没有审计（Rule 15 精神）。

## 审计

### Single Responsibility — 否（不违反）

属性测试只验证不变量；audits.md 只记录审计结论。

### 循环依赖 — 否（不违反）

dev-dependency 不进入发布产物；公共接口不变。

## 新增 Public API

无。

## 影响模块

- **core/Cargo.toml** — 新增 proptest（dev-dependencies）。
- **core/tests/property.rs** — 属性测试（新增）。
- **docs/testing.md** — 「工具（计划）」更新为现状。
- **docs/audits.md** — 审计登记表（新增）。
- **WORKFLOW.md** — Audit 步骤增加落表要求。
- **Roadmap** — 新增 T-032。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个 dev-dependency + 1 个测试文件 + 1 个登记表；
   0 模块 / 0 Public API。
2. **是否是永久性的？** proptest 是长期测试基础设施（dev-only）；审计登记表是长期
   流程产物。
3. **有没有更简单但同样满足需求的方案？** 继续手写用例——边界仍不可穷尽，且无法
   自动缩小失败输入；审计继续口头化——正是本次要修的失败本身。

结论：1 dev-dependency / 1 测试文件 / 0 公共接口，未触及红线。

## 备注

- Swift 侧属性测试与 fuzz（cargo-fuzz）、UI 端到端自动化另列切片，不在本波。
- proptest 关闭默认特性可减少依赖树，但与 criterion 不同，proptest 默认特性无
  wasm 负担，按默认引入即可。
