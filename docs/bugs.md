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
| BUG-013 | IME 点击定位契约违规：`characterIndex(for:)` 把**屏幕坐标**当视图坐标、且返回 **UTF-8 字节偏移**，而 NSTextInputClient 契约（SDK 头文件：point 为屏幕坐标系、返回字符索引，协议全量区间为 UTF-16 单位）要求 UTF-16 索引——CJK 下 IME 点击定位错位（「你好」中「好」= 字节 3，契约索引应为 1；变异复验：旧实现报 3≠1 / 屏幕点报 8≠1） | Fixed | Implementation Bug | — | 4d7c81b | 2026-08-03 |
| BUG-014 | 组合开始忽略 `replacementRange`：选中文本后输入拼音，组合显示在光标处、原选区高亮残留（组合与选区重叠）；替换被推迟到提交，取消组合则选区未删——NSTextInputClient 契约要求 setMarkedText「inserts string replacing the content specified by replacementRange」 | Fixed | Implementation Bug | — | 4d7c81b | 2026-08-03 |
| BUG-015 | 存储失败不可见（ADR-004 打折）：① 缓冲自动保存失败仅 NSLog——崩溃保护失效用户无感知（编辑内容只在内存）；② `setupStorage` 失败（如 ASTER_STORE_DIR 指向普通文件 / 只读目录）静默启动——后续保存只报误导性「文档没有可合并的快照」，用户被卡在保存/丢弃二选一；失败注入测试（目录只读）断言 saveErrorCount 0≠1 | Fixed | Implementation Bug | — | bbdcc8d | 2026-08-03 |
| BUG-016 | 崩溃恢复「忽略」分支只登记最新缓冲文档：多缓冲文档（崩溃遗留 3 个）选「忽略」后仅 latest 登记未决 + 快照序号，其余文档退出「保存全部」不覆盖、干净退出后内容困在缓冲（下次启动不再提示，除非再崩溃）——违反 ADR-013 v1.4 保留规则 3/4「不因忽略而失管 / 不留没被问过的文档」（契约测试：忽略后 id 42/43 未登记） | Fixed | Implementation Bug | — | a2ce6ab | 2026-08-03 |
| BUG-017 | 关闭按钮路径死循环 / 卡死：未决文档存在时点关闭按钮 → 窗口直接消失 → 系统终止流程里才弹未决提示——「保存全部 / 全部不保存」弹窗上下文异常（保存失败→取消→无窗口重触发）、「取消」返回 terminateCancel 后应用无窗口，`applicationShouldTerminateAfterLastWindowClosed` 恒 true，AppKit 反复重触发终止 = 弹窗死循环（独立 repro 实测：取消后连续弹窗直到 watchdog）；Cmd+Q 窗口仍在所以正常 | Fixed | Implementation Bug | — | 0cfdc16 | 2026-08-03 |
| --- | --- | --- | --- | --- | --- | --- |

## 规则

- Bug ID 必填、自增、不可复用。
- Upstream Reference 仅当根因涉及第三方组件或社区已知问题时填写；格式 `组件名 版本 (upstream #编号 / URL)`，注明访问日期。
- 修复完成时回填根因分类与 Commit，并在 [docs/changelog.md](changelog.md) 的 `Fixed` 区引用 Bug ID。
