# ADR-026 — Layout 行区间语义收拢（Bridge 暴露 layout_line_ranges）

- **Status:** Accepted
- **Date:** 2026-08-03
- **Version:** 1.0
- **新增 Public API:** 1 个 Bridge FFI（`layout_line_ranges`）
- **影响模块:** core（bridge、layout）、app（EditorModel）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

行结构（行号 ↔ 字节区间 ↔ 偏移）的语义只能有一个所有者：Core `Layout`
（ADR-009）。Bridge 在既有 `layout_line_starts` 之外新增
`layout_line_ranges(text: String) -> Vec<usize>`（扁平 `[start0, end0, start1,
end1, …]`，语义 = `Layout::line_range`），App 只做机械分块；删除 Swift 侧对
`Layout::line_range` 语义的复刻（`EditorModel.lineRanges` 的「下一行起点 - 1 /
末行到文本末尾」派生）。

App 侧按缓存区间做二分查行（`EditorModel.lineIndex(ofByteOffset:)`）**保留**：
它是缓存数据上的标准二分（Rule 11，注释已存在），逐查询经 Bridge 传 starts
会引入 O(行数) 桥接拷贝（渲染帧每帧查询一次，VertexBuilder），Rule 9 拒绝该
方案；查找是算法而非域状态，行结构的状态（区间本身）已由 Core 单一产出。

## 原因

- **问题证据（2026-08-03 全仓复审，I-010）**：Core `Layout::line_range` /
  `line_at`（core/src/layout.rs）与 Swift `EditorModel.lineRanges` / `lineIndex`
  是同一语义的两份实现——`\n` 归属、末行边界、越界钳制双所有者，Core 调整时
  Swift 副本不会同步。Bridge 只放行了 `line_starts`（ADR-009 的
  `pub(crate)` 内部访问器），迫使 App 复刻剩余语义。
- **宪法 Rule 17（域状态单一所有者）**：行结构域状态（每行的字节区间）被两个
  功能共享（光标定位 / 渲染 / 鼠标命中），必须由唯一模块产出。range 派生回
  Core 即收拢；二分查找是标准算法，不属于域状态。
- **Rule 9 三问第三问**：全量收拢（Bridge 暴露 opaque `LineIndex` 句柄）更彻底
  但新增 opaque 类型与生命周期管理，收益不足；保持现状 = 双实现漂移风险已知。
  中间方案（range 派生回 Core + 查找保留）满足「状态单一所有者」且零热路径
  回归，是最简合规解。

## 审计

### Single Responsibility

bridge 只做机械类型适配（`Layout` 已存在的语义直接透传）；`Layout` 继续只回答
行结构查询，不引入渲染 / 像素语义。

### 循环依赖

`bridge → layout`（单向）；`app → bridge → core`。无新增方向。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `layout_line_ranges(text: String) -> Vec<usize>` | 全文档行字节区间，扁平 start/end 对；复用 `Layout::line_range`（ADR-009 语义，`\n` 属前一行） |

> `layout_line_starts`（既有）保留：行起点是行区间派生的低成本特例，仍被
> Bridge 测试与审计引用；不重复放行。

## 影响模块

- **core（bridge）**：新增 1 个 FFI 函数（`Layout::build` + 逐行 `line_range`
  + 扁平化，约 10 行）。
- **app（EditorModel）**：`lineByteRanges` 改为分块 `layout_line_ranges`
  结果；删除 `lineRanges(of:)` 语义派生；`lines` / `splitLines` 改为复用
  `lineByteRanges` 缓存；`lineIndex(ofByteOffset:)` 不变（标准二分，注释保留）。
- **测试**：Bridge 新增 1 项（扁平区间语义 + 空文本 / 多行）；App
  EditorModelTests 断言随实现迁移（同一期望值）。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个 FFI（约 10 行 Core + 机械分块助手），删除 Swift
   语义派生约 8 行；0 抽象层 / 0 依赖。
2. **是否永久？** 是——行结构单一所有者是永久结构；成本恒定（一次派生调用
   替代一次 `line_starts` 调用，同复杂度 O(n)）。
3. **有没有更简单方案？** 保持现状最省事但已知漂移风险；opaque `LineIndex`
   句柄更彻底但复杂度不降反升。结论：1 FFI 是满足「单一所有者」的最简方案。

## 备注

- 本切片不预做行索引缓存（T-064 后续评估 Core 侧缓存，属性能切片，Rule 16
  需基准前置）。
- 查找保留 App 侧二分不影响本 ADR 的收拢目标：区间数据唯一来源已回 Core，
  Swift 的二分只消费缓存数据。
- 实现切片：T-072（同切片交付消费者——EditorModel.lineByteRanges 接线）。
