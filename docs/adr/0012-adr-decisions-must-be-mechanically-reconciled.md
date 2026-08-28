# ADR 0012：每条 ADR 决策必须映射到可执行校验或显式豁免——机械对账取代「人记得实现」

- 状态：已接受
- 日期：2026-08-28
- 决策者：人 + agent

## 背景

复盘证据反复指向同一个最大的结构性缺口：**「ADR 决策写了、templates 没做」，而没有任何机制在对账。**

- ADR 0009 §1（拦截门禁必须用随机假凭据自证）接受 9 天，`pr-check.yml` / `ci.yml` 的 gitleaks 里零实现；
- ADR 0006（`runs-on` 走变量路由）写进受管规则，本仓 `ci.yml` 四处却硬编码 `ubuntu-latest`；
- ADR 0009 §2「跳过不是通过」，`pr-check.yml` 却仍用 `--if-present`（脚本缺失静默成功）。

12 条 ADR 全靠人记得去实现，已至少 3 条落空。更早还有 a7af3b1：ADR 0010「注册前清理」文档写了、
`onboard-reconcile` 代码没做，代价是两个生产仓 0 runner。**「记得去实现」不是机制**（这正是 ADR 0010
对接入说过的话，只是没用在 ADR 自己身上）。

同型缺口还有一层：templates ↔ 运行体漂移。同一逻辑脚本在模板（本仓）、Mac 运行体（agents-toolchain
`~/.agents`）、xserver 持久源（xserver-bootstrap）三处各有一份，一处改动不会自动传播，且**没有任何工具在
检测分叉**——本会话给 `onboard-reconcile` 加 `.private==true` 时，就是靠手动在三处各改一遍。

## 决策

**每一条 ADR 决策，要么映射到一条可执行校验，要么在豁免表里写明为何没有静态不变量。二者必居其一，机械强制。**

1. **可执行校验**：`docs/adr/checks/NNNN-*.sh`，每个是自足断言，违反即非零退出 + `❌` 说明。当前锁定
   刚修复的三处，防止静默回归：`0006-runner-routing`（无写死 runner，探针/心跳例外）、
   `0009-gate-canary`（密钥扫描必带金丝雀）、`0009-no-silent-skip`（无 `--if-present`）、
   `0012-wired-in-ci`（对账自己必须挂在 CI 上）。
2. **豁免表** `docs/adr/checks/EXEMPT.tsv`：没有静态不变量或由既有守卫测试覆盖的 ADR，写明「在哪被守卫 /
   为何无不变量」（如 0003→test-reasonix-runtime、0010→test-onboard、0002→部署授权策略非代码不变量）。
3. **覆盖强制** `skills/vibedevops/scripts/check-adr-compliance.sh`：跑全部 checks + 断言每条 ADR（0001+）
   要么有 `checks/NNNN-*.sh` 要么在 EXEMPT.tsv。**新 ADR 若两者都缺 → 对账 FAIL**，无法静默漏实现。
   挂进 `ci.yml`（必过），守卫测试 `test-adr-compliance.sh` 反向变异证明每条校验真会红。
4. **运行体漂移**（跨仓，CI 够不着）：`check-runtime-drift.sh` + `runtime-drift-manifest.tsv` 声明
   「同一逻辑脚本」的模板↔运行体对应，本地有克隆时报告漂移量。它只让漂移**可见**（运行体有机器专属
   硬编码，不强制同一），由人判断是有意差异还是漏传播。不进 CI（需跨仓凭据），是人工同步前的对账工具。

## 备选方案

- **OPA/conftest/Rego**：成熟的 policy-as-code，但引入非 bash 依赖，与本仓「bash+git 优先」不合，且对
  YAML/shell 混合模板的断言并不比几行 grep 更清晰。留待校验规模真大到 grep 撑不住时再换。
- **只靠 code review 记得对账**：正是被反复证伪的现状。
- **强制模板↔运行体逐字节一致**：错的——运行体有机器专属硬编码（IP/跳板/路径），一致性检查会永远假红。
  正确的是「让漂移可见 + 人判断」。

## 后果

- 好处：刚修的三处自打脸被机械锁死，回归即红；新 ADR 被逼着「决策与其校验同生」；templates↔运行体漂移
  第一次有工具可查。这是把「每次只修实例、不修产生实例的机制」扭转为修机制。
- 代价：写新 ADR 多一步（加 check 或豁免）——但这一步正是要强制的。checks 用 grep，可能有表述性误报，
  由 `test-adr-compliance.sh` 的反向变异兜底其有效性。
- 技术债：运行体漂移仍靠人跑 `check-runtime-drift.sh`（未进 CI，因跨仓凭据）；若未来跨仓 PAT 就绪，可升级为
  定时对账。checks 目前只覆盖 crisp 且当前满足的不变量，0009 §3/§4 等更难 grep 的条款仍靠 review。
