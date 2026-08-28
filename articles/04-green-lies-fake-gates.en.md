# The day all three of my CI gates lied to me

*Every one of them was green. Every one of them was wrong. And they were all wrong in the same shape.*

I spent a week "fixing" a CI/CD pipeline. Every fix produced green evidence. Every fix was a lie — not because the checks were buggy, but because **the path I verified on was never the path production took.** By the time I understood why, I'd found the same defect wearing three different costumes, all in a single day.

Here they are, because the pattern underneath them is worth more than any of the individual bugs.

## 1. "It builds" — but it built on a different road

The pipeline had an ordinary shape: a **build workflow** that produced an image, and a **deploy workflow** that called it and shipped the image to production. The build workflow also had a manual trigger, so I could verify it in isolation.

For a week I "fixed" it. Trigger the build workflow by hand: green. Merge to main: red. Fix, trigger by hand, green, merge, red. Repeat.

Then I finally read the failing log:

```
env:
  SSH_PRIVATE_KEY:        ← empty
  SSH_HOST:               ← empty
  SSH_USER:               ← empty
  REGISTRY_TOKEN: ***     ← has a value (the one the platform injects automatically)
```

**A reusable workflow does not inherit the caller's secrets.** Only the platform-injected token had a value; everything else was an empty string. But **on a manual trigger, the repo's secrets are available** — so testing that road in isolation was always green.

The way it failed made it worse. An empty hostname went into an `ssh-keyscan`, that command's stderr was swallowed by `2>/dev/null`, and `set -e` made the whole step exit silently. **Not one line of output in the log. Just an exit code of 1.**

Three things had to stack up for this to survive a week:

1. Reusable-workflow secrets don't inherit by default, and the absence shows up as an **empty string, not an error**.
2. The manual trigger was a **different shape from production**, yet I treated it as equivalent verification.
3. `2>/dev/null` ate the only clue.

## 2. "It's verified" — but I verified the artifact that still had the thing in it

Same day. I was slimming down an image. One dependency took meaningful space; I'd checked production data and confirmed the feature was never enabled, so I made it optional. Build, smoke test, green, merge, deploy.

**The app crashed on startup. 502 in production.**

The cause was one line:

```python
def _make_handler(self, ...) -> sdk.EventDispatcherHandler:
```

The top of the file had the standard guard: `try: import X except ImportError: X = None`. That protects **runtime** use. It does not protect a **type annotation**, which is evaluated when the class is defined. `None.Attr` throws immediately, at import time.

Why didn't my smoke test catch it? Because my smoke test ran on the **previous image** — the one that **still had the dependency in it.** I never once verified the artifact that actually lacked it.

> After you remove a dependency, verification has to run on the artifact that genuinely lacks it, and it has to reproduce the full startup path — not run a single `import`. A test performed on the image that still contains the thing is not a test.

## 3. "It's been red for ages, known issue" — it had never scanned anything

The third gate was a secret scanner. It had failed dozens of times, and everyone knew "that one's a false red, just ignore it."

I read the log. It was red because the scanner **itself** was calling an external API to determine the account type, that call failed under our proxy, and the scanner fell into its "needs a paid license" branch.

Which means: **every past "secret scan failed" was not a scan result. That gate had never scanned a single secret.**

And it looked exactly like "found a leak." Nobody could tell the difference from the UI.

## The three bugs are one shape

They look like three independent bugs. They are one structural defect:

> **There is no mechanism guaranteeing that a green/red signal corresponds to the fact it claims to represent.**

- Bug one: green meant "the manual path runs," read as "production runs."
- Bug two: green meant "the old artifact starts," read as "the new artifact starts."
- Bug three: red meant "the scanner broke," read as "the scanner is working."

Stated once, sharply:

**A gate that has never failed is indistinguishable from a gate that does not exist.**

## Four rules you can copy

**① A gate must prove it can fail before it's allowed to pass.**

My secret scan's first step is now to mint a **randomly generated fake credential** in a temp dir and make the scanner scan *that*. If it doesn't catch it, the step goes red and says, in words, "this run's 'scan passed' is not trustworthy." The randomness is deliberate: a hardcoded sample ends up in the repo, gets scanned by the next step, and over time turns into a genuinely suspicious string.

The same applies to rollback logic — **the rollback path has to have been walked in calm times, not used for the first time during an incident.**

**② Skip is not pass.**

Write a guard as a job-level `if:` condition, and when the condition isn't met, the behavior is a **skip** — and a skipped workflow is **green in the UI.** So "refused to deploy" and "deployed successfully" look identical. Interception has to be an **explicit failure**: non-zero exit plus a clear error line, placed as the first step of the first job so downstream `needs:` blocks naturally.

Its cheaper cousin: `npm run lint --if-present` passes silently when the script is missing. Absence of a check should be *loud*, not invisible.

**③ Delete the alternate road; don't document it.**

Rather than mandating "tests must use the production path," delete the differently-shaped entrances: the build workflow keeps only the "called by the deploy workflow" trigger. State the cost honestly — you can no longer "build without deploying." The compensation is to put **"build but don't push" into the PR gate**, which has the same shape as production and doesn't create a second false road.

While you're there, plug a related hole: a manual-deploy entrance defaults to working **against any branch**. Without a branch guard, that's "any branch can deploy to production." In the four repos I scanned, that hole was open in **all of them.**

**④ Don't swallow stderr.**

`cmd 2>/dev/null` plus `set -e` throws away *why it failed* along with the failure. In this incident, one redirected command made an entire deploy step exit with zero output.

The ironic coda: the same afternoon I fixed this, I wrote `git push --quiet 2>/dev/null` — and the push failed across four repos while I saw empty output and nearly called it a success.

## The part that actually took me weeks: a rule is not a mechanism

Here's the confession. I wrote rule ① down as a formal decision. And then I didn't implement it for weeks. I hardcoded a hosted runner in my own CI while a document I'd written told everyone else not to. I left `--if-present` in the very template that preached against it.

I only found out because I audited my own repo adversarially and got the receipts: the canary I'd mandated didn't exist in any workflow. **A decision written in a doc needs a human to read it, remember it, and choose to comply.** That is exactly the "no mechanism ties the signal to the fact" defect, one level up — now the signal is "we decided X" and the fact is "X is implemented," and nothing checks the correspondence.

So the last rule is the one that makes the other four survive contact with a busy week:

**⑤ Every decision maps to an executable check, or is explicitly marked as having none.** A small script runs every stated invariant in CI and — this is the part that matters — fails the build if any decision has *neither* a check *nor* an explicit exemption. You cannot add a rule and forget to enforce it, because forgetting is now a red build. The checker is guarded by mutation tests: break each invariant on purpose and confirm the checker actually goes red, so the judge itself can't quietly rot.

That last clause is not decoration. The most common way I break things is writing a check that can't fail — which is, once more, the same shape as everything above.

## The bottom line

The most expensive thing here was never the downtime. It was **trust.**

A fake gate is more dangerous than no gate. With no gate you know you're exposed, so you're careful. With a fake gate you believe someone is watching, so you stop looking.

Which is why the acceptance criterion for a gate is no longer "is it green." It's:

**Has it proven it can go red?**

---

*The mechanical enforcement described in rule ⑤ — the canary, the "skip is not pass" checks, and the decision-to-check reconciler that fails CI when an invariant is unimplemented — is real bash, small enough to read in an afternoon. If you want the shapes rather than the framework, the five rules above are the whole of it.*
