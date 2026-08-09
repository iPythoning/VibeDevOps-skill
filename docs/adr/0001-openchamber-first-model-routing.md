# ADR 0001：OpenChamber 优先的有限模型降级

- 状态：已接受
- 日期：2026-08-09
- 决策者：用户 / Codex

## 背景

用户主要在 OpenChamber 工作，但 Claude 继续使用原生 App。OpenChamber 可见多个 OpenCode Go 与 OmniRoute 模型，不过“目录可见”不代表凭证、地区和流式响应均可用；跨 App 也没有可靠的宿主级自动接棒。

## 决策

OpenChamber 作为日常控制面，使用按任务类型划分的固定模型 Agent；Claude 原生 App 处理高风险架构和跨 App 复核，Codex 原生 App 仅在 OpenChamber 路由不可用或需要专项视觉验收时介入。额度、限流、上游故障和能力不匹配可触发最多三跳的 fallback；400、工具协议、权限、地区和代码错误不触发盲目换模。OmniRoute Auto 只作为最后恢复手段。

## 备选方案

- 全部交给 OmniRoute Auto：实测能够完成请求，但会选择预设链外模型，不能保证成本、缓存和模型身份。
- 全部跨 App 手工复制对话：上下文污染严重，无法可靠复现 Git 状态。
- 强制所有任务使用 DeepSeek Flash：成本低，但视觉和高风险架构能力不匹配。

## 后果

日常操作集中在 OpenChamber，固定模型会话更利于前缀缓存；额度不足时有明确退路且不会无限重试。代价是 OpenCode Agent 没有有序 fallback 数组：硬失败发生在模型响应前时，需要用户在 OpenChamber 一键选择下一 Agent；跨 App 接棒仍必须通过 Git + HANDOFF，新路由也只有通过最小 smoke test 后才能标记可用。
