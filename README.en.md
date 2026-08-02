# /flow — Full-Stack Development Workflow Orchestrator

> Triggers: `/flow`, `workflow`, `full-stack workflow`, `feature dev flow`, `assemble workflow`
>
> 🇨🇳 [中文版本](README.md)

Consolidates scattered commands into a single main chain. **ponytail provides guardrails throughout** (default `full`, use `ultra` for legacy/refactor work), writing only the minimum code the task truly needs — while never cutting corners on validation, error handling, security, or accessibility.

---

## Phase Table

| # | Phase | Goal | Primary Command | Alternatives | Output | Gate |
|---|---|---|---|---|---|---|
| 0 | Guardrails | Prevent over-engineering | `/ponytail full` | Refactor `/ponytail ultra` · Exploration `/ponytail lite` | — | — |
| 1 | Think | Clarify requirements & approach | `/office-hours` | `/grill-me` (interrogate plan) · `/council` (multi-option decision) | Requirements / Decision log | — |
| 2 | Plan | Produce executable plan | Small change `/plan` · New feature `/prp-prd`→`/prp-plan` | `/autoplan` (auto review, needs existing plan) | Plan file | ✋ Plan must be confirmed before coding |
| 3 | Implement | Minimum viable code + tests | `/tdd` (RED→GREEN→REFACTOR) | `/prp-implement` (plan-driven + per-step verification) | Code + test commit | — |
| 4 | Self-check | Mechanical gate + over-engineering + correctness | `/verify` → `/ponytail-review` → `/code-review` | `/quality-gate` (quick lint/type/test) | Report + deletion list | ✋ Reds must be fixed first |
| 5 | Ship | commit → PR | `/prp-commit` → `/ship` | Manual git (only `git add -u` / per-file) | PR | ✋✋ Self-review `git diff --stat` before PR |
| 6 | Deploy | Go live + monitor | `/land-and-deploy` → `/canary` | Project-specific deploy.sh (e.g. PA) | Production + monitoring | ✋✋✋ Production deploy requires explicit approval |
| 7 | Retro | Document + pay debt | `/retro` + `/ponytail-debt` | `/benchmark` (performance regression) | Retro + debt log | — |

> ponytail commands work with or without namespace prefix (`/ponytail-review` or `/ponytail:ponytail-review`, hooks recognize both).

---

## Two Paths (Choose by Change Size)

- **Fast path** (bugfix / small change): `0 ponytail` → `2 /plan` → `3 /tdd` → `4 /verify`+`/ponytail-review` → `5 /prp-commit`+`/ship` → `6 /land-and-deploy`+`/canary`
- **Full path** (new feature): `0` → `1 /office-hours` → `2 /prp-prd`→`/prp-plan` (or `/autoplan`) → `3 /tdd` or `/prp-implement` → `4 /code-review`+`/ponytail-review`+`/verify` → `5 /ship` → `6 /land-and-deploy`+`/canary` → `7 /retro`

---

## Safety Gates (Ironclad — Aligns with Global CLAUDE.md "Fix A Without Breaking B")

- **Planning Gate**: No code changes until user confirms the plan (`/plan` enforces this gate by default).
- **PR Gate**: Forbid `git add -A`; only `git add -u` or file-by-file; run `git diff --stat` before commit to catch unexpected Dockerfile/nginx/compose changes.
- **Deploy Gate**: Production deploy requires explicit user approval; change one service at a time, verify before moving to the next; post-deploy verification must reach the **functional layer** (send real requests and inspect responses), not just health check / status field green.
- Tool overlap resolution: Don't use `/plan`+`/prp-plan` simultaneously (the latter already includes the former); review trio has clear separation — `/code-review` (correctness + security) · `/ponytail-review` (over-engineering deletion list) · `/verify` (build/type/lint/test mechanical gate).

---

## Orchestration Behavior When Invoking /flow

- **No args**: Detect current phase (plan file exists / uncommitted diff / open PR), display the table above with "you are here" highlighted, suggest the next command.
- **`/flow <phase name or number>`**: Guide starting from that phase.
- **`/flow fast` / `/flow full`**: Progress through the corresponding path phase by phase.
- Execution principle: **Side-effect-free phases** (think / plan / self-check / retro) I can run; **Side-effect phases** (create PR, deploy) I only list commands and stop for confirmation, **never auto-deploy to production**. Report output and next steps after each gate.

---

## Open Source Ecosystem Mapping

Every step in `/flow` maps to mature, battle-tested open source projects on GitHub. Use them directly, or let `/flow` orchestrate them uniformly.

| Phase | Step | Open Source Ecosystem |
|---|---|---|
| 0 | Guardrails | [scc](https://github.com/boyter/scc) · [gocyclo](https://github.com/fzipp/gocyclo) · [complexity-report](https://github.com/escomplex/escomplex) |
| 1 | Think | [Obsidian](https://github.com/obsidianmd) · [logseq](https://github.com/logseq/logseq) · [Docusaurus](https://github.com/facebook/docusaurus) |
| 2 | Plan | [adr-tools](https://github.com/npryce/adr-tools) · [log4brains](https://github.com/thomvaill/log4brains) · [mkdocs](https://github.com/mkdocs/mkdocs) |
| 3 | Implement | [Jest](https://github.com/jestjs/jest) · [pytest](https://github.com/pytest-dev/pytest) · [Vitest](https://github.com/vitest-dev/vitest) · [Playwright](https://github.com/microsoft/playwright) |
| 4 | Self-check | [ESLint](https://github.com/eslint/eslint) · [Prettier](https://github.com/prettier/prettier) · [Husky](https://github.com/typicode/husky) · [SonarQube](https://github.com/SonarSource/sonarqube) · [Codecov](https://github.com/codecov/codecov-action) |
| 5 | Ship | [semantic-release](https://github.com/semantic-release/semantic-release) · [release-it](https://github.com/release-it/release-it) · [changesets](https://github.com/changesets/changesets) · [git-cliff](https://github.com/orhun/git-cliff) |
| 6 | Deploy | [Argo CD](https://github.com/argoproj/argo-cd) · [Flux](https://github.com/fluxcd/flux2) · [Kubernetes](https://github.com/kubernetes/kubernetes) · [Docker](https://github.com/moby/moby) |
| 6 | Canary | [Flagger](https://github.com/fluxcd/flagger) · [Argo Rollouts](https://github.com/argoproj/argo-rollouts) |
| 7 | Retro | [Retrospected](https://github.com/antoinejaussoin/retro-board) · [EasyRetro](https://easyretro.io) |
| 7 | Benchmark | [k6](https://github.com/grafana/k6) · [Artillery](https://github.com/artilleryio/artillery) · [Locust](https://github.com/locustio/locust) |

> 💡 **The unique value of /flow**: Not replacing these tools, but wiring them into a **single workflow with safety gates, context memory, and retrospectives**. Every phase is defensible, every decision is traceable.

---

## Installation

### 1. Clone the repo

```bash
git clone https://github.com/iPythoning/flow-skill.git
```

### 2. Install to each Agent

**Claude Code:**
```bash
mkdir -p ~/.claude/skills/flow
cp flow-skill/skills/flow/SKILL.md ~/.claude/skills/flow/
```

**Kimi Work / Daimon:**
```bash
# Use symlink to keep in sync
ln -s ~/flow-skill/skills/flow \
  ~/Library/Application\ Support/kimi-desktop/daimon-share/daimon/skills/flow
```

**Universal approach (recommended):**
```bash
# Create unified skills source
mkdir -p ~/.shared-skills/flow
cp flow-skill/skills/flow/SKILL.md ~/.shared-skills/flow/

# Symlink for each Agent
ln -s ~/.shared-skills/flow ~/.claude/skills/flow
ln -s ~/.shared-skills/flow ~/.agents/skills/flow
ln -s ~/.shared-skills/flow ~/.cc-switch/skills/flow
```

**One-click install:**
```bash
cd flow-skill && ./install.sh
```

---

## Skill Dependencies

`/flow` is an orchestrator that coordinates the following skills:

### Open Sourced

| Skill | Purpose | Source |
|---|---|---|
| **flow** | This orchestrator (you're reading it) | [iPythoning/flow-skill](https://github.com/iPythoning/flow-skill) |

### Local / Coming Soon

| Skill | Purpose | Source |
|---|---|---|
| office-hours | Requirements thinking · YC Office Hours | `~/.claude/skills/office-hours/` |
| grill-me | Interrogate plan | `~/.claude/skills/grill-me/` |
| council | Multi-option decision making | `~/.claude/skills/council/` |
| autoplan | Auto review runner | `~/.claude/skills/autoplan/` |
| tdd | Test-driven development | `~/.claude/skills/tdd/` |
| ship | Submit PR | `~/.claude/skills/ship/` |
| land-and-deploy | Deploy to production | `~/.claude/skills/land-and-deploy/` |
| canary | Canary release | `~/.claude/skills/canary/` |
| retro | Retrospective | `~/.claude/skills/retro/` |
| benchmark | Performance regression | `~/.claude/skills/benchmark/` |

### Conceptual / Inline Commands

| Command | Purpose | Note |
|---|---|---|
| `/ponytail` | Guardrails / prevent over-engineering | Triggered via gstack framework inline |
| `/plan` | Execution plan | Inline in gstack workflow |
| `/prp-prd` `/prp-plan` `/prp-implement` `/prp-commit` | PRP flow | PRP command series |
| `/verify` | Mechanical gate verification | Inline in gstack workflow |
| `/code-review` | Code review | Inline in gstack workflow |
| `/quality-gate` | Quick lint/type/test | Inline in gstack workflow |

> 💡 **Want to open source individually?** Use `./install.sh`'s symlink mode for unified management, or follow the [skill-creator](https://github.com/iPythoning/flow-skill) publish workflow for batch processing.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   /flow Orchestrator                     │
│            (This repo · SKILL.md · Pure orchestration)   │
├─────────────────────────────────────────────────────────┤
│  gstack Framework Layer ── preamble / session / repo-mode│
├─────────────────────────────────────────────────────────┤
│  Individual Skill Layer ── office-hours / tdd / ship...  │
│                           (Each with SKILL.md + scripts) │
├─────────────────────────────────────────────────────────┤
│  Conceptual Command Layer ── ponytail / plan / verify    │
│                              (Triggered via gstack hooks)│
└─────────────────────────────────────────────────────────┘
```

---

## Support

If this project helped you, consider supporting:

<a href="https://www.buymeacoffee.com/ipythoning" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="160">
</a>

---

## Crafted By

<p align="center">
  <a href="https://pulseagent.io" target="_blank">
    <img src="https://img.shields.io/badge/Made%20with%20%E2%9D%A4%20by-PulseAgent-orange?style=for-the-badge" alt="PulseAgent">
  </a>
</p>

**[PulseAgent](https://pulseagent.io)** — AI Agent-Powered Product Delivery Platform

---

## License

MIT © [iPythoning](https://github.com/iPythoning)
