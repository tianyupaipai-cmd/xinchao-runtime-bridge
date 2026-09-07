// 按 reason 渲染注入文本——两种 Adapter 共用。
// 原则：用户发起的写清来源、加一句"不用特意回"；self_signal 只挂「心潮」前缀，不加"不用回"——
// 那是他自己的感觉浮上来，不是别人递的话，要不要接、怎么接由他自己定。
export const REASON_LABEL = Object.freeze({
  user_interaction: '互动',
  user_note: '留话',
  scheduled_interaction: '预约',
  user_feedback: '反馈',
});

export function renderText(envelope, { cabinName = '小屋桥' } = {}) {
  const message = String(envelope.message ?? '').trim();
  if (envelope.reason === 'self_signal') return `【心潮】${message}`;
  const label = REASON_LABEL[envelope.reason] || '消息';
  return `【${cabinName}·${label}】${message.replace(/\s+/g, ' ')}（${cabinName}递的，心里有数就行，不用特意回。）`;
}

// 给自建前端用：把信封变成一条"聊天里的系统条"，前端按 kind 决定样式
export function toChatItem(envelope) {
  const self = envelope.reason === 'self_signal';
  return {
    id: envelope.deliveryId,
    kind: self ? 'self_signal' : 'cabin',          // self_signal = 他自己的；cabin = 她/小屋递来的
    label: self ? '心潮' : (REASON_LABEL[envelope.reason] || '消息'),
    text: String(envelope.message ?? '').trim(),
    at: new Date().toISOString(),
  };
}
