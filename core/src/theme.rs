//! Theme 模型与 Theme DSL（ADR-010）。
//!
//! 决策依据：
//! - 固定四角色（background / foreground / selection / cursor）：渲染管线实际
//!   需要的颜色集合；键值表会丢失类型保证，枚举 + 映射是未兑现的抽象（宪法 Rule 9）。
//! - 解析失败必须可见且可区分（ADR-004），错误携带原文供 UI 展示。
//! - `rgba()` 是 v1 唯一颜色语法（ADR 总纲示例）；hex / 命名色留给后续配置切片。

/// RGBA 颜色值。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Color {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
}

impl Color {
    /// 构造 RGBA 颜色；u8 通道保证 0..=255 表示合法。
    pub fn rgba(r: u8, g: u8, b: u8, a: u8) -> Self {
        Self { r, g, b, a }
    }

    pub fn r(&self) -> u8 {
        self.r
    }

    pub fn g(&self) -> u8 {
        self.g
    }

    pub fn b(&self) -> u8 {
        self.b
    }

    pub fn a(&self) -> u8 {
        self.a
    }
}

/// 主题：v1 固定四角色（ADR-010）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Theme {
    background: Color,
    foreground: Color,
    selection: Color,
    cursor: Color,
}

impl Theme {
    pub fn background(&self) -> Color {
        self.background
    }

    pub fn foreground(&self) -> Color {
        self.foreground
    }

    pub fn selection(&self) -> Color {
        self.selection
    }

    pub fn cursor(&self) -> Color {
        self.cursor
    }

    /// 解析 Theme DSL 文本；未出现的角色保持默认值。
    ///
    /// 语法（v1 最小集，ADR-010）：唯一区块 `editor { ... }`，行内
    /// `key: rgba(r,g,b,a)`；空行忽略；重复 key 后者覆盖前者（与未来配置
    /// 分层覆盖语义一致）。任何结构问题都返回精确错误而非静默忽略（ADR-004）。
    pub fn parse(input: &str) -> Result<Self, ThemeError> {
        let mut theme = Self::default();
        let mut in_section = false;
        for raw in input.lines() {
            let line = raw.trim();
            if line.is_empty() {
                continue;
            }
            if !in_section {
                if line == "editor {" {
                    in_section = true;
                    continue;
                }
                return Err(ThemeError::UnknownSection(line.to_string()));
            }
            if line == "}" {
                in_section = false;
                continue;
            }
            let Some((key, value)) = line.split_once(':') else {
                return Err(ThemeError::MalformedLine(line.to_string()));
            };
            let color = parse_color(value.trim())?;
            match key.trim() {
                "background" => theme.background = color,
                "foreground" => theme.foreground = color,
                "selection" => theme.selection = color,
                "cursor" => theme.cursor = color,
                other => return Err(ThemeError::UnknownKey(other.to_string())),
            }
        }
        if in_section {
            return Err(ThemeError::MissingCloseBrace);
        }
        Ok(theme)
    }
}

impl Default for Theme {
    /// 深色基线主题。
    ///
    /// 决策依据：编辑器启动、用户主题加载前的兜底；数值为占位，
    /// 正式设计稿通过 `Default` 或内置 DSL 资源替换，不改 API。
    fn default() -> Self {
        Self {
            background: Color::rgba(0, 0, 0, 255),
            foreground: Color::rgba(255, 255, 255, 255),
            selection: Color::rgba(55, 55, 90, 255),
            cursor: Color::rgba(255, 255, 255, 255),
        }
    }
}

/// Theme DSL 解析错误（ADR-010）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ThemeError {
    /// 区块外出现不属于 `editor { ... }` 的内容。
    UnknownSection(String),
    /// 未知角色名。
    UnknownKey(String),
    /// 值不是合法的 `rgba(r,g,b,a)`（通道越界 / 数量不符 / 语法错误）。
    InvalidColor(String),
    /// 行内缺少 `key: value` 结构。
    MalformedLine(String),
    /// 文本结束时 `editor {` 未闭合。
    MissingCloseBrace,
}

/// 解析 `rgba(r,g,b,a)` 值，通道为十进制 0..=255，允许通道间空白。
///
/// 决策依据：错误携带原始值文本而非解析细节，UI 展示时原文即可定位；
/// 行号信息等 UI 真正呈现配置错误时再加（YAGNI，宪法 Rule 9）。
fn parse_color(value: &str) -> Result<Color, ThemeError> {
    let Some(inner) = value
        .strip_prefix("rgba(")
        .and_then(|s| s.strip_suffix(')'))
    else {
        return Err(ThemeError::InvalidColor(value.to_string()));
    };
    let parts: Vec<&str> = inner.split(',').collect();
    if parts.len() != 4 {
        return Err(ThemeError::InvalidColor(value.to_string()));
    }
    let channels: Result<Vec<u8>, _> = parts.iter().map(|p| p.trim().parse::<u8>()).collect();
    let channels = channels.map_err(|_| ThemeError::InvalidColor(value.to_string()))?;
    Ok(Color::rgba(
        channels[0],
        channels[1],
        channels[2],
        channels[3],
    ))
}
