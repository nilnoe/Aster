//! Theme 模型与 Theme DSL 的公共契约测试（ADR-010）。
//!
//! 策略：公共契约走集成测试（docs/testing.md）；Theme 的私有字段
//! 不直接构造，全部经 `parse` / `default` 与访问器验证。

use aster_core::{Color, Theme, ThemeError};

const DSL_FULL: &str = "\
editor {
    background: rgba(0,0,0,255)
    foreground: rgba(255,255,255,255)
    selection: rgba(55,55,90,255)
    cursor: rgba(200,200,200,255)
}";

#[test]
fn theme_parse_full_dsl_sets_all_roles() {
    let theme = Theme::parse(DSL_FULL).unwrap();
    assert_eq!(theme.background(), Color::rgba(0, 0, 0, 255));
    assert_eq!(theme.foreground(), Color::rgba(255, 255, 255, 255));
    assert_eq!(theme.selection(), Color::rgba(55, 55, 90, 255));
    assert_eq!(theme.cursor(), Color::rgba(200, 200, 200, 255));
}

#[test]
fn theme_parse_partial_keeps_defaults() {
    let theme = Theme::parse("editor {\n    background: rgba(1,2,3,4)\n}").unwrap();
    assert_eq!(theme.background(), Color::rgba(1, 2, 3, 4));
    // 未出现的角色保持默认值。
    assert_eq!(theme.foreground(), Theme::default().foreground());
    assert_eq!(theme.selection(), Theme::default().selection());
    assert_eq!(theme.cursor(), Theme::default().cursor());
}

#[test]
fn theme_parse_ignores_blank_lines_and_indent() {
    let theme = Theme::parse("\n\n  editor { \n\tbackground: rgba(0, 0, 0, 255)\n\n}\n").unwrap();
    assert_eq!(theme.background(), Color::rgba(0, 0, 0, 255));
}

#[test]
fn theme_parse_duplicate_key_last_wins() {
    let theme = Theme::parse(
        "editor {\n    background: rgba(1,1,1,255)\n    background: rgba(2,2,2,255)\n}",
    )
    .unwrap();
    assert_eq!(theme.background(), Color::rgba(2, 2, 2, 255));
}

#[test]
fn theme_parse_unknown_key_fails() {
    let err = Theme::parse("editor {\n    accent: rgba(1,1,1,255)\n}").unwrap_err();
    assert_eq!(err, ThemeError::UnknownKey("accent".to_string()));
}

#[test]
fn theme_parse_invalid_color_value_fails() {
    let cases = [
        "editor {\n    background: rgba(256,0,0,255)\n}",
        "editor {\n    background: rgba(1,2,3)\n}",
        "editor {\n    background: red\n}",
        "editor {\n    background: rgba(1,2,3,255\n}",
    ];
    for dsl in cases {
        let err = Theme::parse(dsl).unwrap_err();
        assert!(matches!(err, ThemeError::InvalidColor(_)), "case: {dsl}");
    }
}

#[test]
fn theme_parse_content_outside_section_fails() {
    let err = Theme::parse("background: rgba(1,1,1,255)\n").unwrap_err();
    assert!(matches!(err, ThemeError::UnknownSection(_)));
}

#[test]
fn theme_parse_unknown_section_fails() {
    let err = Theme::parse("sidebar {\n    background: rgba(1,1,1,255)\n}").unwrap_err();
    assert!(matches!(err, ThemeError::UnknownSection(_)));
}

#[test]
fn theme_parse_missing_close_brace_fails() {
    let err = Theme::parse("editor {\n    background: rgba(1,1,1,255)\n").unwrap_err();
    assert_eq!(err, ThemeError::MissingCloseBrace);
}

#[test]
fn theme_parse_malformed_line_fails() {
    let err = Theme::parse("editor {\n    background\n}").unwrap_err();
    assert!(matches!(err, ThemeError::MalformedLine(_)));
}

#[test]
fn theme_default_is_dark_baseline() {
    let theme = Theme::default();
    assert_eq!(theme.background(), Color::rgba(0, 0, 0, 255));
    assert_eq!(theme.foreground(), Color::rgba(255, 255, 255, 255));
    assert_eq!(theme.selection(), Color::rgba(55, 55, 90, 255));
    assert_eq!(theme.cursor(), Color::rgba(255, 255, 255, 255));
}

#[test]
fn color_accessors_roundtrip_channels() {
    let c = Color::rgba(10, 20, 30, 40);
    assert_eq!((c.r(), c.g(), c.b(), c.a()), (10, 20, 30, 40));
}
