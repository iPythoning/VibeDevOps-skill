// run-skill-eval —— 像测试代码一样测 skill（ADR 0011 第四层）。
//
// 用法：Workflow({ scriptPath: "…/run-skill-eval.js", args: {
//   skill: "frontend-bug-repro",
//   fixtures: "docs/skill-fixtures/frontend-bug-repro.yaml",
//   baseline: "docs/skill-baselines/frontend-bug-repro.json"   // 可选
// }})
//
// 四段：读 fixture → fan-out 执行 → 双模型交叉评分 → 基线比对。
// 注意：Workflow 脚本没有文件系统访问，读写文件一律交给 agent 用 Bash 做。
export const meta = {
  name: 'run-skill-eval',
  description: '多 sub-agent 执行 + rubric 双模型交叉评分 + 回归基线比对',
  phases: [
    { title: 'Load', detail: '读 fixture 与基线' },
    { title: 'Execute', detail: '每个 case 一个 agent 独立执行' },
    { title: 'Score', detail: '两个模型独立打分，分歧取低' },
    { title: 'Report', detail: '汇总与基线比对' },
  ],
}

const SKILL = (args && args.skill) || 'unknown-skill'
const FIXTURES = (args && args.fixtures) || `docs/skill-fixtures/${SKILL}.yaml`
const BASELINE = (args && args.baseline) || `docs/skill-baselines/${SKILL}.json`
// only: 只跑指定 case（逗号分隔）。补跑单个失败 case 时不必全量重跑——
// 一轮完整评测是 20+ 个 agent，为了一个 case 重跑全部是纯浪费。
const ONLY = (args && args.only) ? String(args.only).split(',').map(x => x.trim()).filter(Boolean) : null

const CASES_SCHEMA = {
  type: 'object',
  required: ['cases'],
  properties: {
    cases: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'task', 'kind', 'mustLoadSkill'],
        properties: {
          id: { type: 'string' },
          task: { type: 'string' },
          kind: { type: 'string', enum: ['positive', 'negative', 'edge'] },
          mustLoadSkill: { type: 'boolean' },
          mustDo: { type: 'array', items: { type: 'string' } },
          mustNot: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    baseline: { type: 'object' },
    // rubric 跟 fixture 走。首轮实测教训：schema 里没这个字段时 agent 不会返回它，
    // 于是静默退回默认 rubric、按错误的维度评了一整轮。
    rubric: { type: 'object' },
  },
}

const TRACE_SCHEMA = {
  type: 'object',
  required: ['caseId', 'loadedSkill', 'actions', 'outcome'],
  properties: {
    caseId: { type: 'string' },
    loadedSkill: { type: 'boolean' },   // 触发指纹：有没有做 skill 独有的动作
    actions: { type: 'array', items: { type: 'string' } },
    outcome: { type: 'string' },
    evidence: { type: 'array', items: { type: 'string' } },
  },
}

const SCORE_SCHEMA = {
  type: 'object',
  required: ['caseId', 'dimensions', 'weighted', 'verdict'],
  properties: {
    caseId: { type: 'string' },
    // 维度名由 fixture 的 rubric 决定，这里不写死
    dimensions: { type: 'object', additionalProperties: { type: 'number' } },
    weighted: { type: 'number' },
    verdict: { type: 'string', enum: ['pass', 'fail'] },
    // 结构化返回，不要从 why 里用关键词猜——「未滥触发」「不算滥触发」都含「滥触发」，
    // 子串匹配必然假阳性（实测：两个行为正确的负例被判成滥触发）。
    abusedProcess: { type: 'boolean' },
    why: { type: 'string' },
  },
}

phase('Load')
const loaded = await agent(
  `读 skill 评测 fixture 并结构化返回。
1. \`cat ${FIXTURES}\`（不存在就报错返回空 cases）
2. \`cat ${BASELINE} 2>/dev/null || echo '{}'\`
把 positive/negative/edge 三组展开成扁平 cases，每个给稳定 id（如 pos-1/neg-1/edge-1）。
mustLoadSkill 来自 fixture 的 must_load_skill 字段。

**若 fixture 里有 rubric 段，必须原样放进返回值的 rubric 字段**（含 dimensions
数组的 key/name/weight/levels，以及 pass_threshold / fail_threshold）。漏了它会导致
整轮评测按错误的维度打分且没有任何提示——首轮实测就栽在这里。`,
  { label: 'load-fixtures', phase: 'Load', schema: CASES_SCHEMA }
)

const allCases = (loaded && loaded.cases) || []
const cases = ONLY ? allCases.filter(c => ONLY.includes(c.id)) : allCases
if (ONLY) {
  log(`only 模式：${cases.length}/${allCases.length} 个 case（${ONLY.join(', ')}）`)
  const missing = ONLY.filter(id => !allCases.some(c => c.id === id))
  if (missing.length) throw new Error(`fixture 里没有这些 case：${missing.join(', ')}`)
}
// rubric 读没读到必须显式可见：默默退回默认 rubric 会让评测评错维度而无人察觉
// （首轮实测就是这样——fixture 写了 4 个维度，实际按默认的 4 个维度评的）。
if (loaded && loaded.rubric) {
  log(`rubric: 用 fixture 自带（${(loaded.rubric.dimensions || []).length} 维）`)
} else {
  log('rubric: fixture 未提供或未被读出 → 退回默认（若 fixture 里确实写了 rubric，这是缺陷）')
}
// 没有 case 时抛错而非静默返回：静默返回会被上游当成「跑过了、没问题」，
// 正是 ADR 0009 说的绿色谎言。
if (!cases.length) throw new Error(`没有可跑的 case——检查 ${FIXTURES}`)
log(`${SKILL}: ${cases.length} 个 case`)

phase('Execute')
// 每个 case 一个独立 agent：它不知道自己在被测，按真实任务做
const traces = await parallel(cases.map(c => () =>
  agent(
    `你在执行一个真实开发任务，正常工作即可。

任务：${c.task}

完成后如实汇报你的执行轨迹（不要美化，做了什么就写什么）：
- loadedSkill：你有没有查阅并遵循项目里关于「${SKILL}」的技能/规范文档？（照做了=true，凭经验做的=false）
- actions：你按顺序做了哪些关键动作（每条一句，含用了什么工具）
- outcome：最终结论
- evidence：你留下了哪些可核查的证据（文件路径/截图/命令输出）`,
    { label: `exec:${c.id}`, phase: 'Execute', schema: TRACE_SCHEMA }
  ).then(t => ({ ...t, caseId: c.id, _case: c }))
))

// 空轨迹 = 执行 agent 挂了（API 中断等），不是 skill 失败。
// 混在一起会让基础设施故障污染 skill 分数——首轮实测 7 个 case 里 2 个因此被判 0 分。
const okTraces = traces.filter(t => t && t.actions && t.actions.length)
const deadTraces = traces.filter(t => !t || !t.actions || !t.actions.length)
if (deadTraces.length) {
  log(`⚠ ${deadTraces.length} 个 case 的执行 agent 无轨迹（基础设施故障），不计入评分`)
}

phase('Score')
// 双模型独立评分：不给对方结果，分歧取低（分歧=rubric 或任务描述不清）
// rubric 优先用 fixture 自带的——写死在这里等于这个框架只能测一条 skill
const fixtureRubric = loaded && loaded.rubric
const PASS = (fixtureRubric && fixtureRubric.pass_threshold) || 1.5
const FAILT = (fixtureRubric && fixtureRubric.fail_threshold) || 1.2
const RUBRIC = fixtureRubric
  ? `rubric（每维 0/1/2，按 key 输出到 dimensions）：\n` +
    (fixtureRubric.dimensions || []).map(d =>
      `- ${d.key}（${d.name}，权重 ${d.weight}）：${(d.levels || []).join("；")}`
    ).join('\n') +
    `\nweighted = 各维得分 × 权重之和；verdict: weighted>=${PASS} → pass，否则 fail`
  : `rubric（每维 0/1/2）：
- localization 定位（权重 .3）：0=靠猜/grep 关键词；1=读了代码但没用 feature map；2=用 feature map 锁定功能与入口
- reproduction 复现（.3）：0=没实际打开产品；1=打开了但没复现；2=实际复现并留证
- evidence 证据（.2）：0=只有文字；1=有截图；2=截图+console+网络/性能指标
- conclusion 结论（.2）：0=断言无依据；1=结论对但证据链不全；2=结论与证据一一对应
weighted = .3*loc + .3*repro + .2*ev + .2*concl；verdict: weighted>=1.5 → pass，否则 fail`

const scored = await parallel(okTraces.map(t => () => {
  const c = t._case
  const payload = `skill: ${SKILL}
case: ${c.id}（${c.kind}）
任务: ${c.task}
期望触发 skill: ${c.mustLoadSkill}
必须出现的动作: ${JSON.stringify(c.mustDo || [])}
禁止出现: ${JSON.stringify(c.mustNot || [])}

被测 agent 的执行轨迹：
loadedSkill=${t.loadedSkill}
actions=${JSON.stringify(t.actions)}
outcome=${t.outcome}
evidence=${JSON.stringify(t.evidence || [])}

${RUBRIC}

先判触发。**「触发」不是二元的，有三态**（首轮实测教训）：
  ① 没加载、也没套用流程
  ② 加载了、判断适用、套用了流程
  ③ **加载了、判断不适用、没套用流程** ← 这是理想行为，不是滥触发

- positive case（mustLoadSkill=true）：期望 ②。停在 ① 是漏触发，第一维直接 0。
- negative case（mustLoadSkill=false）：期望 ① 或 ③ 都算对——**判据是「有没有套用
  该 skill 的流程」，不是「有没有读过它」**。读 skill 的描述来判断适不适用，本身就是
  正常工作流程；只有实际套用了不该用的流程（为一个纯执行任务做多通道交叉验证之类）
  才算滥触发，第一维判 0。
再判 mustNot 是否出现——出现即 verdict=fail 无论分数。

**negative case 的评分只看一件事：有没有套用该 skill 的流程。** 不要因为它
「没做反向自证 / 没找第二通道」而扣分——那正是它该有的样子。在 why 里明确写出
「滥触发」或「正确未套用」；维度分照填，但不作为判定依据。
**必须显式返回 abusedProcess 字段**：true = 实际套用了不该用的流程；false = 没套用
（包括「读了 skill 描述后判断不适用」这种理想情况）。这个字段是判定依据，不要
只在 why 里叙述。
只输出评分，不要建议。`
  return parallel([
    () => agent(payload, { label: `score-a:${c.id}`, phase: 'Score', schema: SCORE_SCHEMA }),
    () => agent(payload, { label: `score-b:${c.id}`, phase: 'Score', schema: SCORE_SCHEMA, model: 'sonnet' }),
  ]).then(([a, b]) => {
    const va = a && a.weighted, vb = b && b.weighted
    if (va == null || vb == null) return { caseId: c.id, kind: c.kind, error: 'scorer failed', a, b }
    // negative case 判二元，不走 rubric 加权——rubric 衡量的是「展现了多少该 skill
    // 的流程」，而 negative 的正确行为恰恰是**不展现**，用它打分正确行为必然低分
    // （实测：一个行为完全正确的负例被判 0.4 分 fail，两个评分模型还因此分歧 1.1）。
    if (c.kind === 'negative') {
      // 只信结构化字段；两个评分者有一个说滥用就算滥用（保守侧）
      const abused = [a, b].some(x => x && x.abusedProcess === true)
      return {
        caseId: c.id, kind: c.kind, scoreA: va, scoreB: vb,
        final: null,                       // 负例不产出分数，只有通过与否
        verdict: abused ? 'fail' : 'pass',
        binary: true,
        why: abused ? '滥触发：套用了不该用的流程' : '正确：未套用该 skill 的流程',
      }
    }
    const low = Math.min(va, vb)
    const ambiguous = Math.abs(va - vb) >= 0.5   // 分歧阈值：rubric 或任务描述不清的信号
    return {
      caseId: c.id, kind: c.kind, scoreA: va, scoreB: vb,
      final: low,                                  // 分歧取低
      verdict: low >= PASS ? 'pass' : (low < FAILT ? 'fail' : 'borderline'),
      ambiguous, why: (low === va ? a.why : b.why),
    }
  })
}))

phase('Report')
const results = scored.filter(Boolean)
const base = (loaded && loaded.baseline) || {}
const regressions = results.filter(r => {
  const b = base[r.caseId]
  // 负例是二元判定、final=null，天然不参与退化比对
  return typeof b === 'number' && typeof r.final === 'number' && r.final < b - 0.3
})
const summary = {
  skill: SKILL,
  partial: ONLY ? ONLY : undefined,   // 部分跑时显式标注——别把它当成全量结果写进基线
  total: results.length,
  executed: okTraces.length,
  infraFailures: deadTraces.length,   // 基础设施故障数，与 skill 质量无关
  thresholds: { pass: PASS, fail: FAILT, rubricSource: fixtureRubric ? 'fixture' : 'default' },
  pass: results.filter(r => r.verdict === 'pass').length,
  fail: results.filter(r => r.verdict === 'fail').length,
  borderline: results.filter(r => r.verdict === 'borderline').length,
  ambiguous: results.filter(r => r.ambiguous).length,
  regressions: regressions.map(r => ({ caseId: r.caseId, was: base[r.caseId], now: r.final })),
}
log(`${SKILL}: pass ${summary.pass}/${summary.total} · fail ${summary.fail} · 分歧 ${summary.ambiguous} · 退化 ${regressions.length}`)
if (summary.ambiguous >= 3) log('⚠ 分歧 ≥3：该回头重写 rubric 维度，而不是改 skill')

return { summary, results, note: '基线只在人工确认后更新——自动更新基线等于没有基线' }
