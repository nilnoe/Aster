# ADR-023 — Disk 保存语义（写回绑定路径）

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** Core `DocumentManager::save_text` 1 方法 + 2 错误变体；Bridge FFI 1 项
- **影响模块:** core（document_manager、bridge）、app（AppDelegate、AppMenu、EditorModel）、docs
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

1. **保存 = 把当前编辑文本写回 Document 绑定的磁盘路径**。DocumentManager 是注册表与
   路径的唯一所有者（ADR-001）；App 经 Bridge 传入当前会话文本（Editor 是会话状态，
   ADR-017），Core 写文件并同步更新注册表副本，保存点后注册表与编辑会话一致。
2. **错误全部可见（ADR-004）**：未知 id → `UnknownBuffer`；Scratch（无路径）→ 新增
   `NoPath(BufferId)`；写失败 → 新增 `SaveFailed { path, kind }`（携带 io 错误种类，
   UI 可呈现可操作信息）。
3. **v1 直接 `std::fs::write`（非原子写）**：Beta 阶段写回失败可见即可；原子写
   （临时文件 + rename）随 T-029（Crash Recovery / Session）评估，不为本切片引入
   两阶段写入（Rule 9：复杂度预算）。
4. **App 侧最小可用集**：File 菜单「保存」（⌘S）；dirty 状态由 `EditorModel.onChange`
   回调维护（type_text / delete_backward / undo / redo 成功才触发，光标移动与选区
   不置脏），窗口标题加「●」；关闭 / 退出时存在未保存编辑 → NSAlert 三选（保存 /
   不保存 / 取消）。
5. **文本经 Bridge 传回而非让 Core 持有 Editor**：激活文档统一（注册表 ↔ 会话双向
   同步）随 T-024 落地；v1 最小接线避免把激活文档状态提前引入 Core（Rule 9，同
   ADR-017 对激活文档的推迟理由）。

## 原因

- **I-002（审查问题登记）**：编辑器能开不能存——T-015 只有 open 无 write，关窗即丢
  编辑。保存是编辑器的永久能力，不是可选增强。
- **为什么标准库能解决（Rule 11）**：`std::fs::write` 覆盖 v1 需求；不引入临时文件 /
  rename 两阶段写入（见决策 3）。
- **为什么放 DocumentManager 而非 Store**：Disk 文件写回是「存储目标绑定」语义
  （ADR 总纲第 7 节：File 是 Buffer 的存储目标），归属 ADR-001 的 DocumentManager；
  SQLite Store 只承载 Scratch / Session（ADR-013），磁盘文档写回不经过它。

## 审计

### Single Responsibility

DocumentManager 新增「写回存储目标」职责，与「注册 + 生命周期 + 路径绑定」
（ADR-001）同域；不混入渲染、命令分发或编辑语义。

### 循环依赖

`document_manager → buffer / error`（单向）；`bridge → document_manager`；
`app → bridge → core`。无反向。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `DocumentManager::save_text(&mut self, id: BufferId, content: &str) -> Result<(), DocumentManagerError>` | 把 `content` 写回 id 绑定的路径并更新注册文本 |
| `DocumentManagerError::NoPath(BufferId)` | Scratch 文档无路径可写 |
| `DocumentManagerError::SaveFailed { path, kind }` | 文件写入失败（路径 + io 错误种类） |
| Bridge `document_manager_save_text(dm: &mut DocumentManager, id: usize, text: String) -> Result<usize, String>` | 成功返回 id（usize 透传惯例，ADR-014 / ADR-001 v1.1）；错误映射消息字符串 |

## 影响模块

- **core（document_manager）**：新增 save_text + 2 个错误变体；`Document` 字段在
  产品路径首次被读（path / buffer），移除 `expect(dead_code)`。
- **core（bridge）**：新增 FFI 1 项。
- **app**：AppDelegate 持有 currentDocumentId + dirty 状态，实现 saveDocument /
  applicationShouldTerminate 关闭保护；AppMenu 增加「保存」；EditorModel 增加
  onChange 回调（App 模块内，非公共 API）。
- **docs**：changelog / roadmap / audits / benchmarks 同步。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** Core 1 方法 + 2 错误变体 + 1 FFI；App 侧薄胶水（菜单项、
   dirty 标题、关闭保护，约 50 行）；0 抽象层、0 新依赖。
2. **是否永久？** 是——保存是编辑器的永久能力；dirty 与关闭保护是"不静默丢数据"
   的最小产品语义。
3. **有没有更简单方案？** 只做保存、不做 dirty/关闭保护——会保留 I-002 的"关窗静默
   丢编辑"主诉；原子写留给 T-029。结论：当前是满足"能保存 + 不静默丢数据"的最简集。

## 备注

- 打开第二个文件替换当前会话时，前一个文档的未保存编辑仍会丢弃（既有行为，
  随 T-024 激活文档统一）；本切片先提供保存能力与关闭保护。
- 注册表副本与会话分离的边界沿用 ADR-001 v1.1；save_text 使副本在保存点同步。
- 保存成功不弹窗（系统惯例）；失败经 NSAlert 可见（ADR-004）。
