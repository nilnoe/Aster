# Bugs — 缺陷登记表

Bug 在报告阶段登记，编号自增（BUG-001, BUG-002, ...），与 [docs/bug-workflow.md](bug-workflow.md) 配合使用。

状态：`Open` / `Reproducing` / `Fixing` / `Fixed` / `Won't Fix` / `Duplicate`

| Bug ID | 标题 / 现象 | 状态 | 根因分类 | 上游引用 | 修复 Commit | 报告日期 |
| BUG-001 | T-012 文本渲染模糊：Retina（scale=2）下字形被放大采样，边缘发糊 | Fixed | Implementation Bug | — | 见 changelog（fix commit 引用本 ID） | 2026-08-02 |
| --- | --- | --- | --- | --- | --- | --- |

## 规则

- Bug ID 必填、自增、不可复用。
- Upstream Reference 仅当根因涉及第三方组件或社区已知问题时填写；格式 `组件名 版本 (upstream #编号 / URL)`，注明访问日期。
- 修复完成时回填根因分类与 Commit，并在 [docs/changelog.md](changelog.md) 的 `Fixed` 区引用 Bug ID。
