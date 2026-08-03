//! Frame 域收拢测试（T-074，I-012 / I-013）：frame ↔ 文档关联单一所有者。
//!
//! 决策依据：frame 域状态此前散在 AppDelegate.frames / frameFileName 字典 /
//! view.model.bufferIdValue / closeDecisionDocId（I-013，I-012），收拢为
//! `FrameDocument` 后由方法保证登记与更新（Rule 17 / 18：不变量在方法内）。

import AppKit
import XCTest

@testable import AsterApp

@MainActor
final class FrameDocumentTests: XCTestCase {
  func testSetAndQueryFrameDocument() {
    let delegate = AppDelegate()
    let window = NSWindow(
      contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)

    delegate.setFrameDocument(window, documentId: 1, fileName: nil)
    XCTAssertEqual(delegate.frameDocumentId(for: window), 1)
    XCTAssertNil(delegate.frameFileName(window), "Scratch 文档无文件名")

    delegate.setFrameDocument(window, documentId: 2, fileName: "a.txt")
    XCTAssertEqual(delegate.frameDocumentId(for: window), 2, "⌘N / ⌘O 换文档必须更新登记")
    XCTAssertEqual(delegate.frameFileName(window), "a.txt")
    XCTAssertEqual(delegate.frameDocs.count, 1, "同一 frame 只保留一条登记")
  }
}
