//! Editor 单元测试（T-064 拆分，Rule 3：editor.rs 303 行超限——与
//! session/edit.rs 同款模式；child module 可访问私有字段）。

use super::{Buffer, BufferId, Editor, Movement};

/// T-064（Rule 18）：行索引缓存的不变量（移动构建 / 编辑失效）由方法保证——
/// 直接断言状态，避免靠性能测试兜底。
#[test]
fn layout_cache_built_on_move_and_invalidated_on_edit() {
    let mut ed = Editor::new(Buffer::new(BufferId::new(1)));
    ed.type_text("a\nb\nc").unwrap();
    assert!(ed.layout_cache.is_none(), "编辑前无缓存");

    ed.move_cursor(Movement::Down, false);
    assert!(ed.layout_cache.is_some(), "行移动必须构建并保留行索引缓存");

    ed.type_text("x").unwrap();
    assert!(ed.layout_cache.is_none(), "编辑必须失效行索引缓存");

    ed.move_cursor(Movement::LineEnd, false);
    assert!(ed.layout_cache.is_some(), "行内移动再次构建");
    ed.undo().unwrap();
    assert!(ed.layout_cache.is_none(), "undo 必须失效行索引缓存");
}
