> Prefer a simpler architecture over a faster implementation. Every abstraction must justify its lifetime cost.

# Constitution — 项目宪法

- **Version:** 1.2
- **Status:** Accepted

本文件是本项目**不可违反的原则**。它不是编码规范，不讨论格式、命名、风格等可调整事项。

任何规则只有在明确写出的例外条件下才可被打破，且打破本身必须被记录和论证。

优先级：**Constitution 高于一切。** ADR、WORKFLOW、AGENTS 及任何其他文档都不得与本宪法冲突。

---

## Rule 1 — 禁止无证明的抽象层

任何 PR 不允许增加抽象层。

除非能证明：复杂度下降。

新增抽象层时，必须附上复杂度对比论证（增加前 vs 增加后）。

## Rule 2 — Trait / Protocol 必须有理由

任何新增 Trait（Rust）或 Protocol（Swift），必须回答：

> 为什么不能直接实现？

没有明确答案，不允许引入。

## Rule 3 — 文件行数上限

新增文件超过 **300 行**，必须拆分。

## Rule 4 — Public API 必须 ADR

任何新增 Public API，必须先有 ADR。

## Rule 5 — Red → Green → Refactor

任何功能先写测试，测试必须 **Fail**。

然后实现，测试 **Pass**。

最后 **Refactor**，测试保持 Pass。

不允许跳过任何一步。

## Rule 6 — 提交前质量门禁

任何 Commit 之前，Agent 必须运行：

```text
cargo fmt
cargo clippy
cargo test
swift-format
swift test
```

全部通过，否则不能提交。

## Rule 7 — 新增依赖必须论证

新增任何依赖（crate / package），必须解释：

> 为什么标准库不能解决？

## Rule 8 — 新增第三方库必须 ADR

任何新增第三方库，必须有 ADR。

## Rule 9 — 复杂度预算（Complexity Budget）

**代码不是最大的成本，长期维护复杂度才是。**

每一个 PR 都必须回答三个问题：

1. 这个改动增加了哪些复杂度？
2. 这些复杂度是否是永久性的？
3. 有没有更简单但同样满足需求的方案？

三个问题的答案必须随 ADR 或 PR 描述记录，供 Architecture Audit 检查。

红线：如果一个 PR 增加了两个抽象层、三个新模块、四个公共接口，只是为了实现一个很小的功能，这个 PR 应该被拒绝。

## Rule 10 — 注释必须有决策依据

函数的注释应当详尽且有意义，禁止为注释而注释（例如复述代码本身的"设置 x 为 1"）。

注释的价值在于回答"为什么"：

- 为什么这样做，而不是那样做？
- 为什么这里的复杂度是必要的？（可回链 Rule 9）
- 为什么这个边界条件或异常需要特殊处理？
- 是否存在宪法 / ADR 依据？若有，必须引用对应编号。

无法提供决策依据的注释，应当删除而不是保留。

## Rule 11 — 禁止重复造轮子（Reuse First）

永远不要自己重复造轮子。

复用的优先级（从高到低）：

1. 标准库与系统能力（macOS：AppKit、CoreText、IME、Clipboard、Window、Menu 等）
2. 成熟的开源实现（mlua、SQLite、swift-bridge、Metal 生态等）
3. 自研

自研必须有证明：现有方案无法满足需求，或复用成本高于自研成本（回链 Rule 9 复杂度预算）。

"复用优先"不豁免审查：新增依赖仍受 Rule 7 / 8 约束，第三方库仍必须 ADR，且必须锁定版本。

## 修订本宪法

本文件"不可违反"，但允许显式修订：

- 修订必须由项目所有者（nilnoe）确认；Agent 不得自行修改本文件。
- 每次修订必须在 [docs/changelog.md](changelog.md) 记录。
- 每次修订后递增 Version。
- 修订建议应指出：修改哪一条、为什么、影响哪些下游文档。

---

违规不意味着任务失败，但必须在 Architecture Audit 阶段被捕获并修正，然后才能进入 Done。
