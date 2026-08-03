# VibeDevOps — Vibe Coding Without Giving Up Understanding

> Triggers: `/vibedevops`, `understand AI changes`, `project map`, `change summary`, `handoff architecture`
>
> 🇨🇳 [中文版本](README.md) · Formerly `flow-skill` (the `/flow` workflow orchestrator still lives in `skills/flow/`)

**Take all the speed of vibe coding — don't give up the understanding.** VibeDevOps turns "understanding" and "production readiness" from feelings into process and files:

- **Change Explanation Contract** — before and after every change, the AI is forced to produce a readable plan and summary
- **Three-Stage Comprehension Path** — an actionable route from "passively reading along" to "actively in control"
- **Cross-Agent Handoff Architecture** — `AGENTS.md` + `HANDOFF.md` + ADRs + vendor pointer files, so understanding is persisted in the repo and any agent can pick up instantly
- **Production-Grade Guardrails** — secrets baseline (Infisical) / CI trio / rollback runbook / monitoring checklist, as templates and scripts rather than willpower
- **`/vibedevops audit`** — a 0–100 production-readiness score showing whether your vibe project is safe to ship

Pairs with `/flow` in this repo (the workflow backbone: think → plan → implement → verify → ship → deploy → retro): **flow governs "how work gets done", vibedevops governs "whether you — and the next agent — still understand the project".**

---

## 1. Change Explanation Contract (zero cost, use today)

Append this fixed instruction to every change request:

> Before making changes, tell me which files you plan to touch, what changes in each, and why. Wait for my confirmation before starting.
> After completing the changes, output: ① the list of changed files ② a one-line purpose for each file's change ③ if multiple files are involved, how their call relationships changed ④ if new directories or files were introduced, where they sit in the project structure.

Companion habit: run `git diff` after every change and have the AI explain it hunk by hunk. Diffs are the highest-ROI learning material — real, specific, and your own code.

---

## 2. Three-Stage Comprehension Path

| Stage | Timeline | Core | Key Actions |
|---|---|---|---|
| 1. Force the AI to explain | Weeks 1–2 | Change your instructions, not yourself | The contract above + read every `git diff` |
| 2. Build a project map | Weeks 2–4 | Black-box folder → mental map | `tree -L 3` with one-line purpose per directory · walk the main flow from the entry point along the import chain · draw a dependency diagram and update it after every change (living doc) |
| 3. Small-step verification | Week 4+ | Cement understanding with engineering habits | Small commits (each explains why it exists) · **retell test** (explain the change yourself, AI corrects you) · **prediction drill** (guess which files will change; wrong guesses = knowledge gaps) |

---

## 3. Cross-Agent Handoff Architecture

Understanding that lives in chat evaporates with context compression; understanding on disk doesn't. This architecture lets any vendor's agent (Claude / Codex / Cursor / Gemini / Windsurf / Kimi) pick up any repo instantly:

| File | Role |
|---|---|
| `AGENTS.md` | **Single authoritative rulebook**: onboarding three-steps, wrap-up three-musts, verification commands, git discipline, anti-patterns. Vendor files are pointers; conflicts resolve to this file |
| `docs/HANDOFF.md` | Status board: current goal / done / in-progress (with file locations) / known pitfalls / next steps / how to verify |
| `docs/adr/` | Architecture Decision Records — the cure for "why did we change this again". A decision not written down never happened |
| Vendor pointers | `CLAUDE.md` / `GEMINI.md` / `.cursorrules` / `.windsurfrules` / `.github/copilot-instructions.md` — all point to the same AGENTS.md |

**One-shot deployment (idempotent, non-destructive):**

```bash
# 1. Edit the REPOS array in the script with your repo paths
# 2. Dry-run first to review the plan
./skills/vibedevops/scripts/deploy-handoff.sh --dry-run
# 3. Apply (add-only; existing files backed up as .bak before appending; one commit per repo, revertible)
./skills/vibedevops/scripts/deploy-handoff.sh
```

Deployment discipline and pitfalls (macOS bash 3.2 `set -u` empty-array trap, `.gitignore` ignoring `docs/` requires `git add -f`, stale `index.lock`) are documented in [skills/vibedevops/SKILL.md](skills/vibedevops/SKILL.md).

---

## 4. Production-Grade Guardrails (mechanical defenses before/after shipping)

The typical vibe-coder incident isn't misunderstanding code — it's leaked secrets, zero CI, ship-and-pray deploys, and no rollback plan. Every guardrail ships as a **template + script + AGENTS.md rule** trio — never willpower.

### Secrets Baseline (with [Infisical CLI](https://github.com/Infisical/cli))

Three layers; full spec in [templates/security/SECRETS.md](skills/vibedevops/templates/security/SECRETS.md):

- **Keep them out**: pre-commit hook blocks leaks (`infisical scan` → gitleaks → fallback regex); real `.env` never committed
- **Keep them centralized**: `infisical run --env=dev -- <start command>` injects at runtime, nothing on disk; CI uses Universal Auth machine identity — only two credentials in repo secrets
- **Recover when leaked**: rotate first, scrub history later (`git filter-repo`) → check usage logs → write an ADR

### CI Trio ([templates/ci/](skills/vibedevops/templates/ci/))

`pr-check.yml` (secret scan + lint/type/test, with Node/Python/Go swap-in blocks) · `deploy.yml` (GitHub Environments manual approval + Infisical injection + functional-layer smoke test) · standard rollback procedure in the RUNBOOK

### Rollback & Incident Response ([RUNBOOK.template.md](skills/vibedevops/templates/RUNBOOK.template.md))

Ship with an exit (write down "how do I revert this?" before deploying) · database migrations: backup first + expand-contract in two deploys + line-by-line human review of AI-generated destructive SQL · incident three-step: stop the bleeding → root cause → blameless 5-why postmortem filed as an ADR

### Monitoring & Environment ([production-checklist.md](skills/vibedevops/templates/production-checklist.md))

Monitoring four-piece (real `/health`, Sentry, uptime monitor, alerting that reaches a human) · reproducibility acceptance bar: "fresh machine, clone to running ≤ 5 minutes" · [renovate.json](skills/vibedevops/templates/renovate.json) weekly grouped updates (majors get individual human-reviewed PRs)

### `/vibedevops audit` — Production-Readiness Score

Scores any repo 0–100 across 7 dimensions (tests 15 / CI 15 / secrets 20 / monitoring 15 / rollback 10 / environment 10 / handoff docs 15) with a gap list. Scoring rules in [SKILL.md](skills/vibedevops/SKILL.md) §6.

---

## 5. /flow — The Workflow Backbone (formerly flow-skill)

Consolidates scattered commands into a single main chain with **ponytail guardrails throughout** (default `full`, `ultra` for legacy/refactor work): minimum code the task truly needs, never cutting validation, error handling, security, or accessibility.

| # | Phase | Goal | Primary Command | Gate |
|---|---|---|---|---|
| 0 | Guardrails | Prevent over-engineering | `/ponytail full` | — |
| 1 | Think | Clarify requirements | `/office-hours` (alt: `/grill-me`, `/council`) | — |
| 2 | Plan | Executable plan | `/plan` · `/prp-prd`→`/prp-plan` (alt: `/autoplan`) | ✋ Plan confirmed before coding |
| 3 | Implement | Minimal code + tests | `/tdd` (alt: `/prp-implement`) | — |
| 4 | Self-check | Mechanical gate + correctness | `/verify` → `/ponytail-review` → `/code-review` | ✋ Fix reds first |
| 5 | Ship | commit → PR | `/prp-commit` → `/ship` | ✋✋ `git diff --stat` self-check |
| 6 | Deploy | Go live + monitor | `/land-and-deploy` → `/canary` | ✋✋✋ Explicit approval |
| 7 | Retro | Document + pay debt | `/retro` + `/ponytail-debt` | — |

**Safety gates (ironclad):** no code before plan confirmation · no `git add -A`, self-review `git diff --stat` before PR · production deploys require explicit approval, verified at the functional layer (real requests, real responses).

Full details: [skills/flow/SKILL.md](skills/flow/SKILL.md).

---

## Installation

```bash
git clone https://github.com/iPythoning/VibeDevOps-skill.git
cd VibeDevOps-skill && ./install.sh
```

Or install manually — copy/symlink `skills/vibedevops` and `skills/flow` into your agent's skills directory (`~/.claude/skills/`, `~/.agents/skills/`, Kimi Work's daimon skills dir, etc.).

---

## Repository Layout

```
├── skills/
│   ├── vibedevops/          # Comprehension + governance + production guardrails (main)
│   │   ├── SKILL.md
│   │   ├── templates/       # AGENTS.md / HANDOFF.md / ADR / RUNBOOK / vendor pointers
│   │   │   ├── security/    # Secrets baseline: SECRETS.md (Infisical), pre-commit, env.example
│   │   │   ├── ci/          # pr-check.yml / deploy.yml (GitHub Actions skeletons)
│   │   │   ├── production-checklist.md  # Monitoring four-piece + reproducibility
│   │   │   └── renovate.json            # Dependency update baseline
│   │   └── scripts/
│   │       └── deploy-handoff.sh   # Batch rollout (idempotent, --dry-run)
│   └── flow/                # Workflow backbone (formerly flow-skill)
│       └── SKILL.md
├── install.sh
└── README.md / README.en.md
```

---

## Support

<a href="https://www.buymeacoffee.com/ipythoning" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" width="160">
</a>

---

## Credits

<p align="center">
  <a href="https://pulseagent.io" target="_blank">
    <img src="https://img.shields.io/badge/Made%20with%20%E2%9D%A4%20by-PulseAgent-orange?style=for-the-badge" alt="PulseAgent">
  </a>
</p>

**[PulseAgent](https://pulseagent.io)** — AI-Agent-driven product delivery platform

---

## License

MIT © [iPythoning](https://github.com/iPythoning)
