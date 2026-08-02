//! 字形图集分配器（T-012，ADR-016）。
//!
//! 决策依据：水平条带分配（行内从左到右、行满换行、满表拒绝）是 spike 规模下最简的
//! 无重叠分配策略——不需要更复杂的 shelf/guillotine 算法（宪法 Rule 9）。
//! 坐标语义：x 向右、y 向下，与 Metal 纹理行方向一致（ADR-016 GPU 缓冲格式）。

import CoreGraphics

/// 纯几何分配器：不依赖 GPU，可单测（docs/testing.md：可测逻辑抽离）。
struct AtlasPacker {
  let width: Int
  let height: Int
  private(set) var cursorX = 0
  private(set) var cursorY = 0
  private(set) var rowHeight = 0
  private(set) var isFull = false

  /// 分配 `w × h` 像素矩形；图集放不下时返回 `nil` 并置 `isFull`。
  mutating func allocate(width w: Int, height h: Int) -> CGRect? {
    guard !isFull, h <= height, w <= width else { return nil }
    if cursorX + w > width {
      // 行满换行：回到行首，下移一行。
      cursorX = 0
      cursorY += rowHeight
      rowHeight = 0
    }
    guard cursorY + h <= height else {
      isFull = true
      return nil
    }
    let rect = CGRect(x: cursorX, y: cursorY, width: w, height: h)
    cursorX += w
    rowHeight = max(rowHeight, h)
    return rect
  }

  mutating func reset() {
    cursorX = 0
    cursorY = 0
    rowHeight = 0
    isFull = false
  }
}
