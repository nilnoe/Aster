# ADR-010 — Theme 模型与 Theme DSL

- **Status:** Accepted
- **Date:** 2026-08-02
- **Version:** 1.0
- **新增 Public API:** 3 个公开类型（`Color` / `Theme` / `ThemeError`）+ 1 个关联方法（`Theme::parse`）
- **影响模块:** Core（新增 theme 模块）
- **是否违反 Single Responsibility:** 否
- **是否增加循环依赖:** 否

---

## 决策

在 Rust Core 中新增 `theme` 模块：`Color`（RGBA u8 值类型）与 `Theme`（v1 固定四角色：`background` / `foreground` / `selection` / `cursor`），并提供 `Theme::parse` 解析 **Theme DSL**（配置 Layer 1：声明式、无逻辑，ADR 总纲第 4 节）。

Theme DSL 语法（v1 最小集）：

```text
editor {
    background: rgba(0,0,0,255)
    foreground: rgba(255,255,255,255)
}
```

## 原因

- Theme 是 ADR 技术选型中 Core 的明确职责之一，且 DocumentManager（ADR-001）已声明与 Theme 单向协作（会话 / Scratch 的主题属性），Theme 模块必须先行存在。
- **固定四角色而非键值表 / 枚举 + 映射：** 渲染管线（T-012）实际需要的颜色就这四种；字符串键值表会丢失类型保证，枚举 + 映射是未兑现的抽象（宪法 Rule 9：YAGNI）。后续新增角色 = 增加一个字段、一个访问器、一个 DSL key，成本线性。
- **DSL 直接由 Core 解析：** Theme DSL 是 Theme 的规范文本形态（docs/glossary.md）。Lua 接入（T-008）后 DSL→Lua 的转换归属由 T-008 再定，本切片不预判。
- **`rgba()` 是 v1 唯一颜色语法：** ADR 总纲示例只出现 `rgba()`；hex / 命名色属于后续配置切片，需要时再加（Rule 9）。
- **失败必须可见（ADR-004）：** 未知 key / 非法颜色 / 结构错误都以 `ThemeError` 精确表达，不静默忽略。

## 审计

### Single Responsibility — 否（不违反）

theme 模块只做一件事：定义颜色 / 主题值模型，并把 Theme DSL 文本解析成该模型。不涉及渲染、样式计算或配置系统。

### 循环依赖 — 否（不违反）

theme 模块不依赖任何其他 Core 模块；依赖方向：`T-012 渲染 / T-007 Command → Theme`。

## 新增 Public API

| API | 职责 |
| --- | --- |
| `Color::rgba(r: u8, g: u8, b: u8, a: u8) -> Color` | RGBA 颜色值；u8 保证 0..=255 表示合法 |
| `Color::r() / g() / b() / a() -> u8` | 通道访问器（与 BufferId 的 newtype 惯例一致） |
| `Theme::default() -> Theme` | 深色基线主题（渲染前的兜底，数值是占位符，正式设计稿后替换） |
| `Theme::background() / foreground() / selection() / cursor() -> Color` | 四角色访问器 |
| `Theme::parse(dsl: &str) -> Result<Theme, ThemeError>` | 解析 Theme DSL；未出现的角色保持默认值 |
| `ThemeError` | `UnknownSection(String)` / `UnknownKey(String)` / `InvalidColor(String)` / `MalformedLine(String)` / `MissingCloseBrace` |

`Color` 与 `Theme` 派生 `Debug / Clone / Copy / PartialEq / Eq`。不引入 Trait（宪法 Rule 2：当前无抽象需求）。

## 解析规则（v1 契约）

- 仅一个区块 `editor { ... }`；区块外出现任何非空内容 → `UnknownSection`。
- 行内 `key: value`；未知 key → `UnknownKey`；结构不符 → `MalformedLine`。
- 值必须是 `rgba(r,g,b,a)`，通道为十进制 0..=255（允许通道间空白）→ 否则 `InvalidColor`。
- 重复 key：**后者覆盖前者**（与未来配置分层覆盖语义一致）。
- 空行忽略；EOF 时区块未闭合 → `MissingCloseBrace`。
- 语法大小写敏感、不支持注释（v1 不需要，注释语法待 T-008 Lua / 配置切片评估）。

## 影响模块

- **Core（新增 theme 模块）** — 唯一影响；T-012（Metal 渲染）与 T-007（Command，如 `theme.set`）经本模块取色。
- **DocumentManager（ADR-001）** — 声明的单向协作（会话主题属性）在会话 / SQLite 切片落地，本切片不实现。

## 复杂度预算（宪法 Rule 9）

1. **增加了哪些复杂度？** 1 个模块、3 个公开类型、1 个解析函数；约 200 行内，无抽象层、无新依赖。
2. **是否是永久性的？** Theme 模型是永久结构；四角色集合与 `rgba()` 语法可在后续切片线性扩展，不改变已定 API 的形状。
3. **有没有更简单但同样满足需求的方案？**
   - 键值表 `HashMap<String, Color>`：更"通用"，但丢失类型保证且把错误推迟到渲染期，复杂度和调试成本更高；
   - 直接硬编码颜色常量、不做 DSL：无法满足"Theme 由 Theme DSL 描述"（glossary 已定义）。
   - 两者都不满足需求或更复杂，本方案为最简合规方案。

结论：1 模块 / 3 类型 / 1 方法，未触及红线。

## 备注

- 默认主题数值为占位（设计稿切片可经 `Theme::default` 或内置 DSL 资源替换，无需改 API）。
- 行号信息在错误中暂缺（payload 携带原文）；当 UI 需要定位配置错误时再加，属增量而非重构。
- DSL→Lua 的统一 Runtime 归属 T-008，届时评估本模块是否保留 Rust 侧解析或改由 Lua 驱动。
