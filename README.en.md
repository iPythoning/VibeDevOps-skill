# VibeDevOps — Vibe Coding Without Giving Up Understanding

> Triggers: `/vibedevops`, `understand AI changes`, `project map`, `change summary`, `handoff architecture`
>
> 🇨🇳 [中文版本](README.md) · Formerly `flow-skill` (the `/flow` workflow orchestrator still lives in `skills/flow/`)

**Take all the speed of vibe coding — don't give up the understanding.** VibeDevOps turns "understanding" and "production readiness" from feelings into process and files:

- **Change Explanation Contract** — before and after every change, the AI is forced to produce a readable plan and summary
- **Three-Stage Comprehension Path** — an actionable route from "passively reading along" to "actively in control"
- **Cross-Agent Handoff Architecture** — `AGENTS.md` + `HANDOFF.md` + ADRs + vendor pointer files, so understanding is persisted in the repo and any agent can pick up instantly
- **Production-Grade Guardrails** — secrets baseline (zero-dependency-first: Push protection → gitleaks → sops+age) / CI trio / rollback runbook / monitoring checklist, as templates and scripts rather than willpower
- **Build Gate for constrained environments** — three-tier routing (CI → dedicated builder → local fallback) with a hard 10-minute build limit, auto-degradation, and evidence trails
- **`/vibedevops audit`** — a 0–100 production-readiness score; with `--min <score>` it becomes a CI/pre-push gate, not just a report

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

### Secrets Baseline (zero-dependency-first)

Defenses ordered by dependency cost, from zero upward — a system that claims "no willpower required" cannot rest its first line of defense on "the user remembered to install a tool". Full spec in [templates/security/SECRETS.md](skills/vibedevops/templates/security/SECRETS.md):

- **Layer 0 (zero install)**: GitHub Secret scanning + Push protection — server-side, enforced, survives forgotten installs and machine changes; that's why it comes first
- **Layer 1 (single binary)**: gitleaks pre-commit hook (→ Infisical if installed → fallback regex); real `.env` never committed
- **Layer 2 (solo/small-team default)**: sops + age encrypt deploy secrets **into git** ([sops.yaml template](skills/vibedevops/templates/security/sops.yaml)) — zero service dependency, offline-friendly, secrets share the code's lifecycle; repo secrets collapse to a single age key
- **Recover when leaked**: rotate first, scrub history later (`git filter-repo`) → check usage logs → write an ADR
- **Upgrade to [Infisical](https://github.com/Infisical/cli) only when a team arrives** (permission-scoped distribution, central rotation, runtime injection — needs a cloud or self-hosted backend). Running two secret systems is worse than running none; pick one

### CI Trio ([templates/ci/](skills/vibedevops/templates/ci/))

`pr-check.yml` (secret scan + lint/type/test/build) · `deploy.yml` (re-verify merged main + build one immutable artifact with provenance/SBOM + OIDC + functional smoke/canary + automatic rollback) · standard rollback procedure in the RUNBOOK

### Rollback & Incident Response ([RUNBOOK.template.md](skills/vibedevops/templates/RUNBOOK.template.md))

Ship with an exit (write down "how do I revert this?" before deploying) · database migrations: backup first + expand-contract in two deploys + line-by-line human review of AI-generated destructive SQL · incident three-step: stop the bleeding → root cause → blameless 5-why postmortem filed as an ADR

### Monitoring & Environment ([production-checklist.md](skills/vibedevops/templates/production-checklist.md))

Monitoring four-piece (real `/health`, Sentry, uptime monitor, alerting that reaches a human) · reproducibility acceptance bar: "fresh machine, clone to running ≤ 5 minutes" · [renovate.json](skills/vibedevops/templates/renovate.json) weekly grouped updates (majors get individual human-reviewed PRs)

### Build Gate for Constrained Networks ([templates/build-gate/](skills/vibedevops/templates/build-gate/))

For the combination many developers (especially in China) hit all at once: CI free minutes run out **silently**, the laptop can't run the full suite, the home-lab builder drops offline, proxies hijack routes, and Docker Hub is unreachable. The answer is not "get a bigger machine" — it's making *where to verify* an explicit, auto-degrading, evidence-leaving routing decision:

- **Three-tier routing**: CLOUD (CI) → BUILDER (dedicated machine over ssh) → LOCAL (fallback) — same gate command, same evidence file `docs/BUILD-EVIDENCE.md`, only the evidence strength differs
- **Hard 10-minute limit** (`GATE_TIMEOUT`, default 600s): builds are killed on overrun, with duration recorded. A timeout means the build is sick — fix caches/deps/splits, never raise the limit
- **LOCAL pass ≠ done, it's debt**: recorded in a queue and auto-reverified at the start of the *next* build once the builder is reachable — no cron required
- **Runtime registry injection + named cache volumes**: `NPM_REGISTRY` / `PIP_INDEX` env vars work with stock official images (no image rebaking); warm caches cut gate time roughly in half in practice
- **Tamper-evident evidence**: full gate output logged with sha256 + builder image ID recorded

### `/vibedevops audit` — Production-Readiness Score (and Gate)

Scores any repo 0–100 across 7 dimensions (tests 15 / CI 15 / secrets 20 / monitoring 15 / rollback 10 / environment 10 / handoff docs 15) with a gap list. Scoring rules in [SKILL.md](skills/vibedevops/SKILL.md) §6.

Not just a report — with a threshold it blocks:

```bash
./skills/vibedevops/scripts/health-check.sh --min 60 . || { echo "Not production-ready — push blocked"; exit 1; }
```

---

## 5. /flow — The Workflow Backbone (formerly flow-skill)

Consolidates scattered commands into a single main chain: minimum code the task truly needs, never cutting validation, error handling, security, or accessibility. **ponytail is opt-in and lightweight** — off by default, because always-on guardrails (`full`/`ultra`) measurably degrade output quality; invoke `/ponytail lite` explicitly only when over-engineering actually needs suppressing.

| # | Phase | Goal | Primary Command | Gate |
|---|---|---|---|---|
| 0 | Guardrails (optional) | Prevent over-engineering | Off by default — explicit `/ponytail lite` when needed | — |
| 1 | Think | Clarify requirements | `/office-hours` (alt: `/grill-me`, `/council`) | — |
| 2 | Plan | Executable plan | `/plan` · `/prp-prd`→`/prp-plan` (alt: `/autoplan`) | ✋ Plan confirmed before coding |
| 3 | Implement | Minimal code + tests | `/tdd` (alt: `/prp-implement`) | — |
| 4 | Self-check | Mechanical gate + correctness | `/verify` → `/ponytail-review` → `/code-review` | ✋ Fix reds first |
| 5 | Ship | commit → PR | `/prp-commit` → `/ship` | ✋✋ `git diff --stat` self-check |
| 6 | Deploy | Go live + monitor | merge main → promote immutable artifact → canary | Automatic; rollback on functional-gate failure |
| 7 | Retro | Document + pay debt | `/retro` + `/ponytail-debt` | — |

**Safety gates (ironclad):** no code before plan confirmation · no `git add -A`, self-review `git diff --stat` before PR · merge only after green PR CI · merging to main authorizes automatic production deployment, functional verification, and rollback on failure. Delay the merge when a release window is required; never add a second approval after merge.

Full details: [skills/flow/SKILL.md](skills/flow/SKILL.md).

---

## Installation

```bash
git clone https://github.com/iPythoning/VibeDevOps-skill.git
cd VibeDevOps-skill && ./install.sh
```

The installer converges Claude, Codex, OpenCode/OpenChamber, Cursor, Gemini, Qwen, and Windsurf on `~/AGENTS.md` as the single machine-wide authority, then symlinks `skills/vibedevops` and `skills/flow` into every detected agent. Existing vendor configuration is preserved and backed up before the first pointer/import is added.

To install the native Reasonix runtime as well:

```bash
./install.sh --with-reasonix-runtime
```

This idempotently configures the official OpenCode Go provider, stores the API key and credential backups with mode `0600`, sets the supported 85% compaction threshold, and installs a loopback-only `launchd`/`systemd --user` service with `/healthz` verification. On Linux this explicit option authorizes the installer to enable user lingering for post-logout persistence. See the [Reasonix runtime template](skills/vibedevops/templates/reasonix-runtime/README.md).

To install the daily local image-capacity guard:

```bash
./install.sh --with-image-lifecycle
```

It removes Docker images and build cache older than seven days only when no container references them and they are outside the newest five images per repository. It never uses `docker image rm --force` or deletes volumes. `docker builder prune --force` only suppresses the prompt and remains limited to unused cache older than the retention window. The production templates retry cleanup debt and enforce a capacity gate before building, protect current/LKG plus `production`/`rollback` tags after deployment, and enforce daily GHCR retention with 30 newest versions and a six-hour indexing window. See the [image lifecycle template](skills/vibedevops/templates/image-lifecycle/README.md).

The production template uses a fixed failover order: build on the LAN Xserver first and fall back to Mac; transfer the same `linux/amd64` artifact to a GitHub-hosted runner for the primary GHCR push and fall back to Xserver for that push; deploy to cloud only by digest. Configure the read-only `VIBEDEVOPS_RUNNER_READ_TOKEN` and dedicated `xserver` / `mac-builder` runner labels so offline runners are rejected instead of queued indefinitely. The workflow creation timestamp starts a hard 1,800-second deadline; an overdue release never disarms the rollback lease.

After explicitly granting `delete:packages`, run `./install.sh --with-ghcr-retention` for daily account-wide GHCR cleanup. The ordinary Docker guard never expands token scopes implicitly.

Or install manually — copy/symlink `skills/vibedevops` and `skills/flow` into your agent's skills directory (`~/.claude/skills/`, `~/.agents/skills/`, Kimi Work's daimon skills dir, etc.).

---

## Repository Layout

```
├── skills/
│   ├── vibedevops/          # Comprehension + governance + production guardrails (main)
│   │   ├── SKILL.md
│   │   ├── templates/       # AGENTS.md / HANDOFF.md / ADR / RUNBOOK / vendor pointers
│   │   │   ├── security/    # Secrets: SECRETS.md, pre-commit (gitleaks-first), sops.yaml, env.example
│   │   │   ├── ci/          # pr-check.yml / deploy.yml (GitHub Actions skeletons)
│   │   │   ├── build-gate/  # Three-tier build routing + 10-min hard limit + debt reverification
│   │   │   ├── reasonix-runtime/ # Native Reasonix provider + launchd/systemd service
│   │   │   ├── image-lifecycle/ # Local/deployment Docker + GHCR retention
│   │   │   ├── production-checklist.md  # Monitoring four-piece + reproducibility
│   │   │   └── renovate.json            # Dependency update baseline
│   │   ├── references/     # Model routing and CI/CD best practices
│   │   └── scripts/
│   │       ├── deploy-handoff.sh   # Batch rollout (idempotent, --dry-run)
│   │       ├── health-check.sh     # 0–100 readiness score; --min N turns it into a gate
│   │       ├── test-health-check.sh # Positive/negative CI/CD scoring fixtures
│   │       ├── test-install.sh      # Global-rule pointers and skill-install fixtures
│   │       ├── test-reasonix-runtime.sh # Cross-platform native Reasonix fixtures
│   │       └── test-image-lifecycle.sh # Image retention safety fixtures
│   └── flow/                # Workflow backbone (formerly flow-skill)
│       └── SKILL.md
├── .github/workflows/ci.yml # Repository PR/main quality gate
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
