# agy-harness

Turn the **Antigravity CLI (`agy`)** into a *verifiable sub-agent worker* for Hermes (or any
agent that can read a `SKILL.md`): one command per task, machine-checkable result, and every run
logged with its token cost.

> [!WARNING]
> **Not sanctioned by Google.** Driving the Antigravity CLI from a third-party agent is called out
> in the [Antigravity Terms of Service](docs/TERMS.md) as a possible breach, and may lead to
> suspension of your Antigravity / Gemini CLI accounts. Use a separate, disposable Google account;
> never your work account. For production automation use the official APIs instead.
> Read **[docs/TERMS.md](docs/TERMS.md)** before installing.

Built because "the sub-agent said it worked" is not evidence.

```
agy_task.sh  →  runs agy with a brief + template
             →  writes RESULT.json / META.json / artifacts
             →  validates the payload (not just the exit code)
             →  prints VERDICT|PASS|FAIL and appends a ledger line
agy_verify.sh → re-runs the same checks any time, 0 LLM tokens
agy_usage.sh  → cost & latency summary
```

## Why it exists

Raw `agy -p "..."` is easy to call and easy to fool yourself with. In practice:

- `agy` returns **`status: SUCCESS` with an empty response** when a tool was auto-denied headless
- `--json-schema` hangs in v1.5.13
- `--mode plan` writes a plan instead of answering
- the same trivial brief can cost **10k or 82k tokens** depending on tool iterations
- sub-agents retry on their own and inflate timeouts until your quota is gone

This harness closes all of that with one wrapper, one verifier, and one ledger.

## Requirements

| Requirement | Notes |
|---|---|
| `agy` (Antigravity CLI) | **not bundled** — install it from your Antigravity account, `agy --version` must work |
| A logged-in `agy` | isolated `AGY_HOME` holding the OAuth token (see Login) |
| bash + python3 | no pip packages, no third-party deps |

## Install

**Option 1 — as a Hermes skill (tap):**
```bash
hermes skills tap add <owner>/agy-harness
hermes skills install <owner>/agy-harness/agy-harness
```
Then put the bundled scripts on PATH (they ship inside the skill dir):
```bash
<skill dir>/bin/install.sh      # or copy <skill dir>/bin/agy_*.sh into ~/.local/bin
```

**Option 2 — clone + installer (most complete):**
```bash
git clone https://github.com/<owner>/agy-harness
cd agy-harness
./install.sh
```

**Option 3 — single file (limited):**
```bash
hermes skills install https://raw.githubusercontent.com/<owner>/agy-harness/main/skills/agy-harness/SKILL.md
```
Only `SKILL.md` is installed — you lose templates and the scripts. Fine for reading, not for working.

## Login (once)

```bash
export AGY_HOME="$HOME/.agy-home"
HOME="$AGY_HOME" agy -p "Reply with exactly: PONG" --output-format json
```
Open the printed URL, consent, paste the code back into the **same terminal** (60-second window,
PKCE — the URL is bound to that process). Token lands in
`$AGY_HOME/.gemini/antigravity-cli/antigravity-oauth-token`.

## Use

```bash
# sanity
agy_task.sh --task smoke --text "Reply with exactly: PONG" --timeout 120

# real work: analysis with a template
agy_task.sh --task audit-auth \
  --template analysis \
  --set "target=src/auth" \
  --set "questions=1) mana yang bisa gagal diam-diam? 2) mana yang menelan error?" \
  --allow-writes --workdir "$(pwd)" --timeout 420 --print-response

# prove it afterwards (anyone can re-run this, costs nothing)
agy_verify.sh --task audit-auth --expect-file HASIL.md

# what did it cost?
agy_usage.sh --days 7
```

Templates: `analysis`, `code-change`, `review`, `report-json`.
Good briefs read like *target + questions + proof required*, not *"check this"*.

## Examples, use cases, FAQ

| Document | What's inside |
|---|---|
| [`docs/PATHS.md`](docs/PATHS.md) | three ways to call agy (direct / sub-agent / cron) + when to use which |
| [`docs/USECASES.md`](docs/USECASES.md) | six real scenarios with **measured** token costs, including one that ate 95k tokens for nothing |
| [`examples/`](examples/) | ready-to-paste briefs: JSON extraction, second opinion, small code change |
| [`docs/FAQ.md`](docs/FAQ.md) | "do I need a sub-agent?", "why exit 65?", "why so expensive?" |
| [`docs/TERMS.md`](docs/TERMS.md) | **the terms risk**: exact quote, risk per usage pattern, sanctioned alternatives |

Rule of thumb: if the job would take you **under 5 minutes** by hand, don't spend ~10k tokens on it.

## Exit codes

| Exit | Meaning |
|---|---|
| 0 | success **and** `VERDICT|PASS` |
| 65 | empty response (tool auto-denied) — runner retries once with `--allow-writes` |
| 66 | `--expect-json` but the answer wasn't JSON |
| 70 | agy succeeded but the verifier rejected the result |
| 124 | timeout |
| 2 | bad args / unfilled template placeholders |

## Cost reality (measured)

| Scenario | Wall | Tokens |
|---|---|---|
| text only | 7s | 9,700 |
| template `report-json` + read a file | 16s | 12,000 |
| template `analysis` (small file) | 84s | 27,500 |
| write one file, 3 in parallel | 74s | 45,500 |
| read + compute, 3 in parallel | 214s | 82,100 |

Parallel is not free: 3 concurrent runs were ~2x slower and ~2.6x more expensive, with no 429s.
**Default to at most 2 parallel workers.**

## Env vars

| Var | Default | Purpose |
|---|---|---|
| `AGY_BIN` | `agy` on PATH | executable location |
| `AGY_HOME` | `~/.agy-home` | isolated HOME with the OAuth token |
| `AGY_STATE_DIR` | `~/.local/state/agy` | task dirs + `ledger.jsonl` |
| `AGY_BIN_DIR` | script dir | where `agy_run.sh` etc. live |
| `AGY_SKILL_DIR` | skill dir | where `templates/` live |
| `AGY_MODE` | `local` | `ssh` runs agy on a remote host (`AGY_HOST`, `AGY_KEY`) |
| `OUTLINE_ENV_FILE` | `~/.config/outline-keton.env` | credentials for `--outline` publishing |

## Layout

```
.
├── install.sh                  # copies scripts to PATH + skill to Hermes skills dir
├── skills/agy-harness/
│   ├── SKILL.md                # the contract (agent-readable)
│   ├── templates/*.md          # brief templates
│   └── bin/                    # agy_task.sh, agy_run.sh, agy_verify.sh, agy_usage.sh, agy_to_outline.py
└── docs/CONTRACT.md            # full behaviour, ledger schema, security notes
```

## Security notes

- `--allow-writes` makes `agy` able to read/write files and run commands in the task workdir.
  Run it in a container, a throwaway dir, or a git worktree — not in a repo you care about.
- The ledger records paths and token counts, never prompt contents.
- Never commit `AGY_HOME`: it contains OAuth tokens.

## License

MIT for this harness. **`agy` itself is not included** and remains subject to Antigravity's own
terms — you install it yourself, with your own account and quota.
