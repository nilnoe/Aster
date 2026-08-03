//! 主线程卡死看门狗（BUG-018 诊断补充，2026-08-03）。
//!
//! 决策依据：BUG-018 用户报告「新建 frame 后关闭卡死，菊花旋转」——菊花 = 主
//! 线程长时间不响应；进程内穷尽复现（posted 事件 / real alert / GPU render）均
//! 正常，说明触发路径与真实环境相关（终止重触发时序 / 窗口服务器状态）。为让
//! 下一次出现可直接定位：主线程 RunLoop 心跳（能跑 = 活着）+ 后台探针（心跳
//! 超过 3s 未更新 = 主线程阻塞），卡死时 NSLog 持续时长与最后心跳时刻（ADR-004：
//! 本地日志，默认无遥测，不上报）。若用户仍能复现，控制台输出即为卡死时间窗。

import Foundation
import os

/// 主线程心跳 + 后台探针。AppDelegate 启动时 start / 退出（applicationWill
/// Terminate 与 deinit）时 stop。
/// `@unchecked Sendable`（Rule 10 决策依据）：看门狗的全部跨线程共享 =
/// `heartbeat`（OSAllocatedUnfairLock 原子读 / 写）；timer / probe 的引用只在
/// 主线程创建与停用（stop 幂等，Timer.invalidate 与 DispatchSource.cancel 均为
/// 线程安全）。为让非隔离的 AppDelegate.deinit 能确定性 stop 而标注，无真实
/// 竞态。
final class MainThreadWatchdog: NSObject, @unchecked Sendable {
  private var heartbeatTimer: Timer?
  private var probe: DispatchSourceTimer?
  /// 主线程最后心跳时刻。写入方 = 主线程 timer；读取方 = 后台探针（锁保护）。
  /// `nonisolated(unsafe)`：OSAllocatedUnfairLock 自身 Sendable，仅标注绕过
  /// Swift 6 的隔离检查（单一数据点、锁保护的原子访问，Rule 9：不为诊断
  /// 工具引入 actor 抽象）。
  private nonisolated(unsafe) let heartbeat = OSAllocatedUnfairLock(initialState: Date())

  func start() {
    guard heartbeatTimer == nil else { return }
    // BUG-018 教训：Timer(target:selector:) 强持有 self 形成保留环——必须用
    // block 版 + 弱捕获；stop() 由 AppDelegate 退出路径确定性调用。
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
      self?.heartbeat.withLock { $0 = Date() }
    }
    RunLoop.main.add(timer, forMode: .common)
    heartbeatTimer = timer

    let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    source.schedule(deadline: .now() + 3, repeating: 1.0)
    source.setEventHandler { [weak self] in
      guard let self else { return }
      let last = self.heartbeat.withLock { $0 }
      let stalled = Date().timeIntervalSince(last)
      if stalled > 3 {
        NSLog(
          "[watchdog] 主线程疑似卡死 %.1f 秒（最后心跳 %@）。若出现在关闭 / 退出流程，请连同本行反馈。",
          stalled, last as NSDate
        )
      }
    }
    source.resume()
    probe = source
  }

  func stop() {
    heartbeatTimer?.invalidate()
    heartbeatTimer = nil
    probe?.cancel()
    probe = nil
  }
}
