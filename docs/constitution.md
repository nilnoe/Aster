> Prefer a simpler architecture over a faster implementation. Every abstraction must justify its lifetime cost.

# Constitution — 项目宪法

- **Version:** 1.4
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

任何文件（新增或修改后）超过 **300 行**，必须拆分。

任何文件必须能用一句话概括单一职责；不能概括、或职责超过一个，即构成**上帝文件**，必须拆分。

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

## Rule 12 — 规模预算（Scale Budget）

代码量必须设上限，禁止上帝文件（Rule 3）。

- **单文件：** ≤ 300 行（Rule 3），且必须满足单一职责。
- **逻辑模块：** ≤ 1,200 行。
- **项目总量：** Rust Core ≤ 20,000 行，Swift App ≤ 5,000 行，合计 ≤ 25,000 行；测试与文档不计入。
- **预警线：** 总量达到预算 80% 时，必须进行精简审计。
- **扩容：** 只有新功能无法在预算内合理实现时才允许；必须 ADR + 用户确认；单次扩容 ≤ 当前预算 25%；优先用精简抵消。
- **精简：** 重复模式出现 ≥ 3 处必须提取或复用（Rule of Three）；死代码立即删除；未兑现的抽象（YAGNI）在精简审计中撤销并更新对应 ADR。
- **封装与接口：** 默认隐藏内部实现（`private` / `pub(crate)`）；任何 `pub` 都是决策，公共 API 必须先 ADR（Rule 4）。

阈值与触发条件的执行细则见 [docs/scale.md](scale.md)。

## Rule 13 — ADR 必须闭环（Decisions Must Close）

任何被 Accepted 且需要代码落地的 ADR，必须在其所在发布周期内进入 Roadmap（有归属切片），或显式标记 Deferred（注明原因与重新评估条件）。

实现与已接受决策出现偏离（方向相反、能力缺失、以替代方案实现而未修订 ADR）视为违规，必须由 Architecture Audit 捕获；处置只有两种：修代码回到决策，或走 ADR 修订流程（需用户确认）。不允许"先欠着"进入 Done。

依据：ADR-004（os_log + tracing）被 Accepted 后从未排期实现，App 至今使用 NSLog；ADR-018 的 Lua 主题方向一度无归属切片。

## Rule 14 — 无消费者的公共接口禁止交付（No API Without a Consumer）

新增 Public API 必须与真实调用方同一切片交付；确需先行验证的 spike 必须显式标注"验证用"，并在 Architecture Audit 中决定保留或撤销。

为"未来需求"预留的接口不允许进入 main（YAGNI）。既有无消费者接口必须在接线切片或精简审计中处置（接线或撤销），不得长期悬挂。

依据：Command / Event / Lua / Store / DocumentManager / Theme 六个模块提前建成且 App 零消费者；Rule 12 约束存量撤销，本规则约束入口。

## Rule 15 — 文档完整性是机械门禁（Docs Integrity Is Mechanical）

ADR 索引完整性（所有 Accepted ADR 必须出现在索引且链接有效）、版本单一来源同步（core 版本 / changelog / tag 一致）、关键文档交叉引用的一致性，由 CI 机械检查，不允许依赖人工记忆。

涉及 ADR / Roadmap / Changelog 的变更必须同步索引与相关文档；CI 检查不通过不得合入。

依据：ADR-018 被索引漏登，changelog / roadmap 却反复引用；文档漂移此前只靠人工发现。

## Rule 16 — 性能决策必须数据驱动（No Performance Decision Without a Baseline）

性能是产品的第一等关切；任何涉及性能权衡的架构变更（存储结构、渲染策略、桥接方式、缓存策略），动手前必须有可复现的基准基线，并在切片 DoD 中报告对比。

没有基线不允许替换数据结构、不允许宣称性能收益或"无显著影响"。数据结构选择必须基于真实负载基准（ADR-006 评估框架），不允许凭直觉定型。

依据：ADR-006 的 String → Rope/Gap 决策依赖基准，而基准体系与基线长期 TBD；"Benchmark 是常态"此前是名义执行。

## 修订本宪法

本文件"不可违反"，但允许显式修订：

- 修订必须由项目所有者（nilnoe）确认；Agent 不得自行修改本文件。
- 每次修订必须在 [docs/changelog.md](changelog.md) 记录。
- 每次修订后递增 Version。
- 修订建议应指出：修改哪一条、为什么、影响哪些下游文档。

---

违规不意味着任务失败，但必须在 Architecture Audit 阶段被捕获并修正，然后才能进入 Done。
