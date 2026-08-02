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
| BUG-007 | 拼音组合期间组合文本超出右缘不自动横向滚动：`setMarkedText` 只更新组合与重绘，未调用 `scrollCursorIntoView`（与 `insertText` 不一致），组合末尾光标超出视口 | Fixed | Implementation Bug | — | 1d7dfe7 | 2026-08-02 |
| BUG-008 | 光标从 ASCII 行 ↓ 进入 CJK 行后落在字符内部（非 UTF-8 边界）：`move_cursor` 字节列目标未钳制到字符边界，后续 type_text / delete_backward 全部报 InvalidCharBoundary、按键静默丢失（违反 ADR-005 底线；属性测试差分排除 Up/Down，无覆盖） | Fixed | Implementation Bug | — | 29bdf9d | 2026-08-02 |
| BUG-009 | 启动默认 Buffer 无 dirty「●」与退出保护：`onChange` 只在 open() 接线，makeMainWindow 创建的默认文档未接线，编辑不置脏、退出不提示（T-041 修复） | Fixed | Implementation Bug | — | c4b4710 | 2026-08-02 |
| BUG-010 | 打开多个文件后「保存全部」互相覆盖、先打开文档内容丢失：`open(_:)` 让所有磁盘文件继承同一个 `currentSnapshotSeq`，`saveAllPending` 逐个合并到同一快照文件，后写覆盖先写（复现测试 BugReproTests：快照实际内容为「+编辑B内容B」，内容A 丢失） | Fixed | Implementation Bug | — | 435e3a0 | 2026-08-02 |
| BUG-011 | 崩溃恢复后多文档保存链路断裂：恢复分支创建新文档并置脏，但**不把内容写入缓冲**（新 id 无 scratch 行）→ ⌘S / 保存全部 `store_load_scratch` 失败；同时**其余未决缓冲文档未登记快照序号** → 保存全部 guard 失败 → 退出只能选「不保存」丢弃（复现测试 BugReproTests：退出返回 terminateCancel + 保存错误提示） | Fixed | Implementation Bug | — | 435e3a0 | 2026-08-02 |
| BUG-012 | undo 回退到与快照一致的内容后仍标记未保存（假 dirty）：undo/redo 无条件触发 onChange → mark + 写缓冲，不比较内容是否已与快照一致（复现测试 BugReproTests：保存后输入再 undo，pendingDocs 仍含该文档） | Fixed | Implementation Bug | — | 435e3a0 | 2026-08-02 |
| --- | --- | --- | --- | --- | --- | --- |

## 规则

- Bug ID 必填、自增、不可复用。
- Upstream Reference 仅当根因涉及第三方组件或社区已知问题时填写；格式 `组件名 版本 (upstream #编号 / URL)`，注明访问日期。
- 修复完成时回填根因分类与 Commit，并在 [docs/changelog.md](changelog.md) 的 `Fixed` 区引用 Bug ID。
