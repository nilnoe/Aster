//! MetalView 的坐标换算 / 滚动可见性扩展（T-075 拆分，Rule 3：MetalView 316
//! 行超限——MetalView+Input 同款模式，T-073 引入宽度测量缓存后超线）。
//!
//! 决策依据：点 ↔ 字节换算、内容尺寸测量、光标可见性是同一组视图几何职责
//! （ADR-019）；从骨架（事件采集 / 编辑接线 / 生命周期）拆出，保持单一职责。
//! 被访问成员从 private 提升为 internal 仅为跨文件扩展访问：仍在 App 模块内，
//! 不构成公共 API（Rule 4 / Rule 12 的封装在模块边界内成立）。

import AppKit

@MainActor
extension MetalView {
  // MARK: - 坐标换算

  /// 点 → 字节偏移（鼠标命中；internal：IME 扩展 firstRect 需要，模块内封装）。
  func byteOffset(at point: NSPoint) -> Int {
    let lineHeight = renderer.lineHeightPts
    let contentY = viewport.scrollY + (bounds.height - point.y)
    let lineIndex = min(max(0, Int(contentY / lineHeight)), model.lineCount - 1)
    let lineStart = model.lineByteRanges[lineIndex].lowerBound
    let layout = LineLayout(text: model.lineText(lineIndex), font: renderer.font)
    // T-018：渲染 x = 内容 x - scrollX，鼠标命中换算反向补偿。
    let x = point.x - renderer.leftPadPts + viewport.scrollX
    return lineStart + layout.byteOffset(atX: max(0, x))
  }

  /// 内容尺寸：高度 = 行数 × 行高；宽度 = 可见行最大宽度 + 左右留白
  /// （ADR-019 决策 1，不取全文档最宽行；右留白随 BUG-006：否则行末光标
  /// 滚到最右时被 clamp 吃掉留白，光标仍会贴边消失）。
  func contentSize() -> CGSize {
    let height = CGFloat(model.lineCount) * renderer.lineHeightPts
    let lineWindow = viewport.visibleLineRange(
      lineCount: model.lineCount,
      viewportHeightPts: bounds.height,
      lineHeightPts: renderer.lineHeightPts
    )
    // T-073（I-014）：内容未变 + 窗口未变时复用上次测量——滚动只平移视口，
    // 不再对可见行重复 shaping（T-038 修了 buildVertices 内部，这里补跨事件重复）。
    let key = (model.contentVersion, lineWindow.lowerBound, lineWindow.upperBound)
    let width: CGFloat
    if let cached = measuredWidthKey, cached == key {
      width = measuredWidthValue
    } else {
      var w: CGFloat = 0
      for lineIndex in lineWindow {
        w = max(
          w,
          renderer.leftPadPts
            + LineLayout(text: model.lineText(lineIndex), font: renderer.font).width
        )
      }
      measuredWidthKey = key
      measuredWidthValue = w
      width = w
    }
    return CGSize(width: width + renderer.rightPadPts, height: height)
  }

  /// 编辑 / 移动后把光标带进视野（internal：IME 扩展 insertText 提交后调用）。
  func scrollCursorIntoView() {
    let line = model.lineIndex(ofByteOffset: model.cursorByte)
    let lineRange = model.lineByteRanges[line]
    let layout = LineLayout(text: model.lineText(line), font: renderer.font)
    // BUG-004：组合期间光标在组合文本末尾（显示文本内联），横向可见性用同一位置。
    let cursorX = caretGeometry.contentX(
      lineRange: lineRange, caretByte: model.caretDisplayByte, layout: layout)
    let lineTop = caretGeometry.lineTop(line: line)
    viewport.ensureCursorVisible(
      cursorX: cursorX,
      lineTop: lineTop,
      lineHeightPts: renderer.lineHeightPts,
      leftPadPts: renderer.leftPadPts,
      rightPadPts: renderer.rightPadPts,
      contentSize: contentSize(),
      viewportSize: bounds.size
    )
  }
}
