//! Event 总线（ADR-011）。
//!
//! 决策依据：
//! - Event 是 Core 向外的唯一通知通道：UI / 插件只订阅、响应，不反向控制（ADR 总纲）。
//! - 订阅返回 id 且可退订：T-008 插件卸载 / UI 重建需要，否则订阅永久泄漏（Rule 9）。
//! - v1 单变体 `BufferEdited`：编辑语义的最小事件，payload 由 T-013 扩充。

use std::fmt;

use crate::buffer::BufferId;

/// 订阅者处理器。
///
/// 决策依据：私有类型别名，仅用于消化 `dyn Fn` 的冗长签名（clippy
/// type_complexity）；不公开，不构成公共 API（Rule 4）。
type Subscriber = Box<dyn Fn(&Event)>;

/// Core 向外发出的事件（v1）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// Buffer 内容发生变化（编辑 / 撤销 / 重做）。
    BufferEdited { id: BufferId },
}

/// 订阅句柄。
///
/// 决策依据：newtype 隐藏内部表示（与 BufferId 惯例一致）；id 只由
/// `subscribe` 产生，不公开构造，避免调用方伪造无效句柄。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SubscriptionId(usize);

/// 事件总线：订阅 → 广播。
#[derive(Default)]
pub struct EventBus {
    subscribers: Vec<(SubscriptionId, Subscriber)>,
    next_id: usize,
}

impl EventBus {
    pub fn new() -> Self {
        Self::default()
    }

    /// 订阅事件；返回用于退订的句柄。
    pub fn subscribe(&mut self, handler: impl Fn(&Event) + 'static) -> SubscriptionId {
        let id = SubscriptionId(self.next_id);
        self.next_id += 1;
        self.subscribers.push((id, Box::new(handler)));
        id
    }

    /// 退订；未知 / 已退订的 id 返回 `false`（幂等）。
    ///
    /// 决策依据：UI 销毁路径可能重复退订，不 panic；bool 让调用方可见
    /// 失败（ADR-004），又比 Result 少一个错误类型（Rule 9）。
    pub fn unsubscribe(&mut self, id: SubscriptionId) -> bool {
        let before = self.subscribers.len();
        self.subscribers.retain(|(sid, _)| *sid != id);
        self.subscribers.len() != before
    }

    /// 广播事件给全部订阅者。
    ///
    /// 契约（ADR-011）：`&self` 借用在编译期阻止处理器于广播期间重入总线
    /// （再次广播或退订都需要 `&mut self`），订阅者应保持纯观察。
    pub fn emit(&self, event: &Event) {
        for (_, handler) in &self.subscribers {
            handler(event);
        }
    }
}

impl fmt::Debug for EventBus {
    /// 处理器是 `dyn Fn`，无法派生 Debug；只暴露订阅数量。
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("EventBus")
            .field("subscriber_count", &self.subscribers.len())
            .finish()
    }
}
