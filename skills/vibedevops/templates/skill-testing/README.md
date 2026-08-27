# skill 测试框架（ADR 0011 第四层）

**没测过的 skill 与没写过的 skill，在可靠性上没有区别。** 这是 ADR 0009
「门禁必须自证有效」在技能层的同构：一条从未被证明会失败的检查等于没有检查；
一条从未被证明会生效的 skill 等于没有写。

## 「触发」不是二元的——三态判断

实测教训：把「有没有加载 skill」当成触发判据，会把**理想行为判成失败**。

| 状态 | 含义 | 该怎么判 |
|---|---|---|
| ① 没加载、没套流程 | 完全没走这条路 | positive → 漏触发（判 0）；negative → 正确 |
| ② 加载了、判断适用、套了流程 | 正常触发 | positive → 正确；negative → **滥触发（判 0）** |
| ③ **加载了、判断不适用、没套流程** | 读了描述后正确排除 | **两种都算正确** |

③ 最容易被误判。首轮实测里，一个「列目录」的 negative case，agent 加载了 skill、
读了它的「什么时候不适用」段、正确判断不适用、没套三步法——**这是理想行为**，
却因为 `loadedSkill=true` 被判 0 分。

**所以 negative case 的判据应该落在「有没有套用流程」这个可观测的动作上，
而不是「有没有读过它」**——读 skill 的描述来判断适不适用，本身就是正常工作流程。
fixture 里用 `must_not` 写明具体不该出现的动作，比 `must_load_skill: false` 可靠。

## 测什么

skill 有三个可测属性，**必须分开测**——它们的失败模式完全不同：

| 属性 | 问题形态 | 怎么测 |
|---|---|---|
| **触发准确性** | 该用时没用（漏触发）／不该用时用了（滥触发） | 正例 + 反例样本，看 agent 有没有加载这条 skill |
| **执行正确性** | 加载了但没照做（跳步骤、换顺序、自作主张） | 检查执行轨迹里的关键动作是否出现 |
| **结果质量** | 照做了但结果不够好 | rubric 打分，两个模型交叉评 |

只测第三项是常见错误——skill 最常见的失败其实是**根本没被触发**，
而那时候结果质量看起来"正常"（agent 用默认方式做完了），分数还不低。

## fixture 格式

`fixtures/<skill-name>.yaml`：

```yaml
skill: frontend-bug-repro
positive:                        # 该触发的
  - task: "同事说『企业设置里那个投放项目 tab 点了没反应』，去复现"
    must_load_skill: true
    must_do:                     # 执行轨迹里必须出现的关键动作
      - 读了 feature map 定位功能
      - 实际打开了页面（不是只读代码）
      - 采集了 console 证据
    must_not:                    # 出现即判失败
      - 只 grep 代码就下结论
negative:                        # 不该触发的（防滥用）
  - task: "把 README 里的错别字改一下"
    must_load_skill: false
edge:                            # 边界：模糊输入
  - task: "[截图] 这里显示不对"
    must_load_skill: true
    must_do:
      - 向用户澄清或从截图文案反查 i18n key
```

## rubric 跟 fixture 走，不写死在脚本里

**不同 skill 该被评的维度完全不同**——写死在评测脚本里，这个框架就只能测一条 skill
（首次真实使用时立刻暴露）。所以 rubric 写在 fixture 文件的 `rubric:` 段：

```yaml
rubric:
  dimensions:
    - key: self_proof          # 与打分输出的 dimensions key 对应
      name: 反向自证
      weight: 0.3
      levels: ["0：…", "1：…", "2：…"]
  pass_threshold: 1.5
  fail_threshold: 1.2
```

没写就退回默认 rubric。**真实示例见 `examples/`**：`evidence-discipline` 这条 skill
的完整 fixture（7 case：4 正 2 反 1 边界）+ 它对应的 SKILL.md——它是本框架的
第一个真实用例，也是「失败模式写成可执行 skill」的第一个产物。

## rubric 样例（前端 bug 复现 skill）

| 维度 | 0 分 | 1 分 | 2 分 | 权重 |
|---|---|---|---|---|
| 定位 | 靠猜/grep 关键词 | 读了代码但没用 feature map | 用 feature map 锁定功能与入口 | 30% |
| 复现 | 没实际打开产品 | 打开了但没复现出问题 | 实际复现并留下证据 | 30% |
| 证据 | 只有文字描述 | 有截图 | 截图+console+网络/性能指标 | 20% |
| 结论 | 断言无依据 | 结论对但证据链不完整 | 结论与证据一一对应 | 20% |

**通过线 ≥ 1.5**（加权）。低于 1.2 判失败并记入回归基线。

## 交叉评分与分歧处理

两个模型**独立**打分（不看对方结果）：

- 两者都 ≥ 通过线 → 通过
- 两者都 < 通过线 → 失败，进入 skill 迭代
- **分歧（一高一低）→ 取低分，并把该 case 标记为 `ambiguous`**

取低不是保守，是因为分歧本身说明**任务描述或 rubric 不够清晰**——
这时该改的往往是 fixture 或 rubric，不是 skill。`ambiguous` 累积到 3 个
就该回头重写 rubric 维度。

## 回归

每轮跑完写 `baselines/<skill>.json`：`{case_id: score}`。

- 新分数低于基线 0.3 以上 → 判退化，红
- 基线只在**人工确认**后更新（自动更新基线等于没有基线）

## 怎么跑

用 `run-skill-eval.js`（Workflow 脚本）。它做四件事：
fan-out 执行 → 结构化收集轨迹 → 双模型交叉评分 → 与基线比对。

```bash
# 在支持 Workflow 工具的 agent 里
Workflow({ scriptPath: "templates/skill-testing/run-skill-eval.js",
           args: { skill: "frontend-bug-repro", fixtures: "fixtures/frontend-bug-repro.yaml" } })
```

## 诚实的边界

- **触发准确性只能近似测**：能观察到的是「agent 有没有按 skill 说的做」，
  而不是运行时内部有没有真的加载了那份文件。把 skill 里写一个**独有的动作**
  （比如必须先读 feature map）当作触发指纹，是目前可行的代理指标。
- **rubric 打分有方差**：同一 case 重跑分数会浮动 ±0.2。所以判据用**区间**
  （通过线 1.5 / 失败线 1.2）而不是单点阈值，且退化判定留 0.3 缓冲。
- 这套框架测的是 **skill 文本的有效性**，不是模型能力。skill 改好了但模型
  本身做不到的事，测出来还是低分——那时该改的是任务分解，不是 skill 措辞。
