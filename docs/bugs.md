# Bugs — 缺陷登记表

Bug 在报告阶段登记，编号自增（BUG-001, BUG-002, ...），与 [docs/bug-workflow.md](bug-workflow.md) 配合使用。

状态：`Open` / `Reproducing` / `Fixing` / `Fixed` / `Won't Fix` / `Duplicate`

| Bug ID | 标题 / 现象 | 状态 | 根因分类 | 上游引用 | 修复 Commit | 报告日期 |
| BUG-001 | T-012 文本渲染模糊：Retina（scale=2）下字形被放大采样，边缘发糊 | Fixed | Implementation Bug | — | 1d6f6d9 | 2026-08-02 |
| BUG-002 | 光标 / 选区高亮 / IME 下划线不可见：纯色 quad 采样到图集透明像素 | Fixed | Implementation Bug | — | 2c3e44f | 2026-08-02 |
| BUG-003 | 拼音组合期间按回车不提交：keyDown 无条件拦截回车插入换行并清空组合 | Fixed | Implementation Bug | — | 4ca16dd | 2026-08-02 |
| BUG-004 | IME 组合期间光标不跟随：光标画在组合起点而非组合文本末尾 | Fixed | Implementation Bug | — | d1337a3 | 2026-08-02 |
| BUG-005 | 文本区鼠标指针是箭头而非 I 型：视图未注册 iBeam 光标矩形 | Fixed | Implementation Bug | — | c12e615 | 2026-08-02 |
| BUG-006 | 横向滚动后行末光标消失 / 回车后左侧边距消失：`ensureCursorVisible` 无左右边缘留白——右缘光标 quad 整体出视口；左缘（回车到新行行首）scrollX 被设成 cursorX，12pt 左边距被滚出视口 | Fixed | Implementation Bug | — | 98cfb30 | 2026-08-02 |
| BUG-007 | 拼音组合期间组合文本超出右缘不自动横向滚动：`setMarkedText` 只更新组合与重绘，未调用 `scrollCursorIntoView`（与 `insertText` 不一致），组合末尾光标超出视口 | Fixed | Implementation Bug | — | 本切片 | 2026-08-02 |
| --- | --- | --- | --- | --- | --- | --- |

## 规则

- Bug ID 必填、自增、不可复用。
- Upstream Reference 仅当根因涉及第三方组件或社区已知问题时填写；格式 `组件名 版本 (upstream #编号 / URL)`，注明访问日期。
- 修复完成时回填根因分类与 Commit，并在 [docs/changelog.md](changelog.md) 的 `Fixed` 区引用 Bug ID。
