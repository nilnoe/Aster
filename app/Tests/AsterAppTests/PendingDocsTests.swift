//! 多文档未提交状态登记测试（T-046，ADR-013 v1.4）。
//!
//! 决策依据：全程检查所有文档状态是纯集合语义，单测覆盖
//! （docs/testing.md：抽出的逻辑）。
import XCTest

@testable import AsterApp

final class PendingDocsTests: XCTestCase {
  func testMarkAndContainsPerDocument() {
    var pending = PendingDocs()
    XCTAssertTrue(pending.isEmpty)
    pending.mark(1)
    pending.mark(3)
    XCTAssertEqual(pending.count, 2)
    XCTAssertTrue(pending.contains(1))
    XCTAssertFalse(pending.contains(2))
  }

  func testCommitRemovesOnlyThatDocument() {
    var pending = PendingDocs()
    pending.mark(1)
    pending.mark(2)
    pending.commit(1)
    XCTAssertFalse(pending.contains(1), "已合并的文档不再是未提交")
    XCTAssertTrue(pending.contains(2), "其他文档不受影响（打开新文件不得抛弃前一个）")
  }

  func testDiscardAndDiscardAll() {
    var pending = PendingDocs()
    pending.mark(1)
    pending.discard(1)
    XCTAssertTrue(pending.isEmpty)

    pending.mark(1)
    pending.mark(2)
    pending.discardAll()
    XCTAssertTrue(pending.isEmpty)
  }

  func testMarkIsIdempotent() {
    var pending = PendingDocs()
    pending.mark(5)
    pending.mark(5)
    XCTAssertEqual(pending.count, 1)
  }
}
