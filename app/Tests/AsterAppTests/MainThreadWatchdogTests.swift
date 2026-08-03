//! 主线程看门狗冒烟测试（BUG-018 诊断补充）。
//!
//! 决策依据：看门狗是诊断仪表，卡死路径无法确定性测试（制造真实主线程阻塞会
//! 挂起测试进程）；本用例只验证接线不崩溃（start → 主 RunLoop 心跳一拍 →
//! stop），防未来误删启动 / 停止调用。

import XCTest

@testable import AsterApp

final class MainThreadWatchdogTests: XCTestCase {
  func testStartStopRunsOneHeartbeatWithoutCrashing() {
    let watchdog = MainThreadWatchdog()
    watchdog.start()
    // 主线程跑一拍：心跳 timer（1s 周期）不保证触发，但 stop 路径必须安全。
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    watchdog.stop()
    watchdog.stop()  // 幂等
  }
}
