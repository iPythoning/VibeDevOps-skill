# OpenChamber 优先的多模型路由

## 控制面

- **日常主入口：OpenChamber。** Kimi K3、Kimi K2.7 Code、DeepSeek V4 Pro/Flash 和 OmniRoute 应急路由都从这里使用。
- **Claude：原生 App。** 负责高风险架构、需求澄清、复杂方案复核，以及 OpenChamber 无法完成的视觉/推理任务。
- **Codex：原生 App 兜底。** 当前 OpenChamber 中可见的 Codex/GPT 路由不等于可用；只有通过最小实请求后才能纳入自动链。
- **Reasonix：后台专项执行器。** 原生 Reasonix 可保持运行，但 OpenChamber 的 `Reasonix-Go` 只是遵循相同纪律的 OpenCode Agent，不等于调用了 Reasonix 进程。

App 是入口，Git、`AGENTS.md` 和 `docs/HANDOFF.md` 才是状态。任何跨 App 切换都必须以可提交的仓库事实交接。

## 默认职责

| 任务 | 首选 | 第二选择 | 最后保障 |
|---|---|---|---|
| 高频扫描、小修复、测试归类 | OpenChamber / DeepSeek V4 Flash | Kimi K2.7 Code | DeepSeek V4 Pro |
| 复杂编码、跨模块实现 | OpenChamber / Kimi K2.7 Code | DeepSeek V4 Pro | Kimi K3 |
| 超长上下文、大仓理解、图像/PDF | OpenChamber / Kimi K3 | Claude 原生 App | Codex 原生 App |
| 高风险架构、不可逆变更、模糊需求 | Claude 原生 App | Kimi K3 反证 | DeepSeek V4 Pro 落地 |
| UI 实现与视觉验收 | Codex 原生 App | Kimi K3 | Claude 原生 App |
| 所有固定路由都额度不足 | OmniRoute `auto/best-coding` 或 `auto/best-reasoning` | 当前仍可用的最适合模型 | 停止写入并报告 |

Kimi K3 不再默认只读：它承担长上下文、视觉输入、复杂仓库理解和长时任务。DeepSeek Flash 的优势是低成本稳定循环，不承担图片理解。简单任务只用一个模型。

## OpenChamber 内部 fallback 链

按任务类型选择一条链，不要把所有模型串成一条万能链：

- `fast`：`deepseek-v4-flash → kimi-k2.7-code → auto/best-coding-fast`
- `code`：`kimi-k2.7-code → deepseek-v4-pro → auto/best-coding`
- `long-context`：`kimi-k3 → kimi-k2.7-code → auto/best-reasoning`
- `vision`：`kimi-k3 → Claude 原生 App → Codex 原生 App`。图片结论结构化后，才可交给 DeepSeek 写代码。
- `architecture`：`Claude 原生 App → kimi-k3 → auto/best-reasoning`

OmniRoute Auto 是最后一跳，因为它会选择链外模型；它的目标是恢复服务，不是保持模型身份、成本或缓存。

### 自动化边界

OpenCode Agent 配置一次只绑定一个模型，没有原生的有序 fallback 数组。模型仍能返回响应时，可按本规则生成 HANDOFF 并切到下一 Agent；如果额度错误发生在模型开始响应之前，模型本身不可能调用下一模型，此时由用户在 OpenChamber 中一键选择下一 Agent。单请求内真正自动降级只能交给 OmniRoute Combo，但其 Auto 可能选择上述固定链之外的模型。

## 何时允许换模

以下情况可进入下一跳：

- 明确额度或余额不足：HTTP 402、quota/credits/spending limit exhausted。
- HTTP 429 在一次短退避重试后仍失败。
- 上游 5xx、连接超时或 provider unavailable 在一次重试后仍失败。
- 模型不支持当前输入能力，例如图片、上下文长度或必要工具调用。

以下情况**禁止**靠换模掩盖：

- HTTP 400、工具 schema、缺失工具名、坏会话重放：先修请求或新建 Session。
- 编译、测试、类型检查失败：这是代码证据，不是额度错误。
- 权限、密钥或地区限制：标记该路由不可用，修配置前不要反复重试。
- 安全拒答或用户输入不完整：停止并说明原因。

## 有限状态机

1. 当前模型最多重试一次；429/5xx 使用短退避，确定性 402/403 不重试。
2. 写入 `docs/HANDOFF.md` 的“模型路由状态”：任务类型、当前模型、错误类别、时间和下一跳。
3. 同一 OpenChamber Session 内换模仅限工具协议兼容；400、工具表变化或上下文污染时新建 Session。
4. 一次任务最多跨三个模型；第三跳仍失败就停止，禁止 fallback 死循环。
5. 跨 App 前先把当前改动验证并提交；无法提交时明确记录未提交文件，下一棒先检查 diff。
6. 已失败路由进入本任务冷却，不再重复尝试；新任务必须先做最小 smoke test 才能解除。

## 缓存纪律

- DeepSeek Flash 长任务保持 provider、model、system prompt、工具清单和前置文件顺序稳定。
- 不复制其他 App 的整段聊天；只追加任务契约、Git 状态、决策、验证证据和下一动作。
- 把动态日志、时间戳和临时输出放在消息尾部，避免破坏稳定前缀。
- 模型或工具表变化就是新的缓存边界；在明确接棒点切换，不在每轮之间来回跳。
- 缓存命中率是上游按实际前缀计算的结果，任何环境变量都不能“锁定 90%”。

## 接棒载荷

换 App 或模型前在 `docs/HANDOFF.md` 写清：

- 当前写入者、App/模型、状态（写入中/待接棒/只读审查）。
- 分支、HEAD、工作树状态和准确文件位置。
- 当前目标与可执行验收标准。
- 已运行命令、结果和失败证据。
- 任务类型、已尝试模型、不可用原因、下一 fallback。
- 未验证假设、风险、禁止事项和下一棒唯一动作。
- UI/视觉任务的截图、页面状态与验收点。

下一棒先核对 Git 事实；HANDOFF 与 Git 不一致时，以 Git 为准并先修正交接状态。
