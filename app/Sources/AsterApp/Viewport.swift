//! 视口滚动状态（T-018，ADR-019）。
//!
//! 决策依据：
//! - 滚动是视图层状态（ADR-017 / ADR-019）：Core 不持有像素坐标；本类型只回答
//!   「滚到哪、如何钳制、如何把光标带进视野」——纯几何，不碰字体 / 模型 / Metal，
//!   因此可离屏单测（docs/testing.md：抽出的逻辑）。
//! - 内容宽度按可见行最大宽度计算（ADR-019 决策 1）；测量需要字体 shaping
//!   （LineLayout），由视图层完成后再传入，本类型保持单一职责，不引入 CoreText。
//! - scrollX 是 v1 永久能力（ADR-019）；软换行（T-019）开启后本类型不变，
//!   视觉折行映射属渲染层。

import CoreGraphics

/// 视口滚动状态：scrollX / scrollY（点），钳制与光标可见性（ADR-019 决策 1）。
struct Viewport {
  private(set) var scrollX: CGFloat
  private(set) var scrollY: CGFloat

  init(scrollX: CGFloat = 0, scrollY: CGFloat = 0) {
    self.scrollX = scrollX
    self.scrollY = scrollY
  }

  /// 平移并钳制；delta 是内容坐标增量（事件符号约定由调用方负责）。
  mutating func pan(
    deltaX: CGFloat, deltaY: CGFloat, contentSize: CGSize, viewportSize: CGSize
  ) {
    scrollX += deltaX
    scrollY += deltaY
    clamp(contentSize: contentSize, viewportSize: viewportSize)
  }

  /// 钳制到 [0, 内容尺寸 - 视口尺寸]；内容小于视口时归零（长行才有横向滚动）。
  mutating func clamp(contentSize: CGSize, viewportSize: CGSize) {
    scrollX = min(max(0, scrollX), max(0, contentSize.width - viewportSize.width))
    scrollY = min(max(0, scrollY), max(0, contentSize.height - viewportSize.height))
  }

  /// 把光标带进视野：横向移出右边缘时滚到可见（ADR-019 决策 1）；
  /// 纵向行为与原实现一致（ADR-017）。
  mutating func ensureCursorVisible(
    cursorX: CGFloat, lineTop: CGFloat, lineHeightPts: CGFloat,
    contentSize: CGSize, viewportSize: CGSize
  ) {
    if lineTop < scrollY {
      scrollY = lineTop
    }
    let lineBottom = lineTop + lineHeightPts
    if lineBottom > scrollY + viewportSize.height {
      scrollY = lineBottom - viewportSize.height
    }
    if cursorX < scrollX {
      scrollX = cursorX
    }
    if cursorX > scrollX + viewportSize.width {
      scrollX = cursorX - viewportSize.width
    }
    clamp(contentSize: contentSize, viewportSize: viewportSize)
  }

  /// 可视行窗口（半开区间）：渲染顶点与内容宽度测量共用（Rule of Three 提取，
  /// 原内联逻辑在 TextRenderer.buildVertices / MetalView.clampScroll 各一份）。
  func visibleLineRange(
    lineCount: Int, viewportHeightPts: CGFloat, lineHeightPts: CGFloat
  ) -> Range<Int> {
    guard lineCount > 0, lineHeightPts > 0 else { return 0..<0 }
    let first = min(max(0, Int(scrollY / lineHeightPts)), lineCount - 1)
    let visibleCount = Int((viewportHeightPts / lineHeightPts).rounded(.up)) + 1
    let last = min(lineCount, first + visibleCount)
    return first..<last
  }
}
