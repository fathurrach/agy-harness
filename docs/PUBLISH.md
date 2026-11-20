# Publishing & release checklist

Repo: <https://github.com/fathurrach/agy-harness> · default branch `main` · MIT (harness only).

## What can be installed how

| Audience | Command | Gets |
|---|---|---|
| Hermes user, wants the full thing | `git clone … && ./install.sh` | skill + scripts + templates |
| Hermes user, wants it as a skill | `hermes skills tap add fathurrach/agy-harness` then `hermes skills install fathurrach/agy-harness/agy-harness` | whole skill dir (SKILL.md, templates, bin/) |
| Hermes user, minimal | `hermes skills install https://raw.githubusercontent.com/fathurrach/agy-harness/main/skills/agy-harness/SKILL.md` | SKILL.md only — no templates/scripts |
| OpenClaw user | `hermes skills publish --to clawhub skills/agy-harness` (from an authenticated machine) | listed in ClawHub |
| Search discovery | `hermes skills publish --to github --repo <collection-repo> skills/agy-harness` | appears in `hermes skills search` |

Layout requirement: Hermes taps read `repo/skills/<name>/SKILL.md`. Do not move skills out of
`skills/` or they become invisible to `tap add`.

## Release checklist

1. bump `version:` in `skills/agy-harness/SKILL.md` (semver: behaviour change = minor, breaking
   contract change = major)
2. run the local gates:
   ```bash
   bash -n skills/agy-harness/bin/*.sh
   python3 -m py_compile skills/agy-harness/bin/*.py
   ./install.sh                       # on a scratch HOME: HOME=$(mktemp -d) ./install.sh
   ```
3. verify a clean-machine install end-to-end (this is the gate that actually matters):
   ```bash
   NEW=$(mktemp -d)
   env -i HOME=$NEW PATH=/usr/local/bin:/usr/bin:/bin AGY_BIN=/path/to/agy \
       AGY_HOME=/path/to/logged-in-home bash ./install.sh
   # expect: "VERDICT|PASS|install-smoke"
   ```
4. update `README.md` cost table if the measured numbers moved
5. commit, push to `main`, then `gh repo view fathurrach/agy-harness` to confirm
6. after pushing, re-check the raw URL that the README advertises:
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' \
     https://raw.githubusercontent.com/fathurrach/agy-harness/main/skills/agy-harness/SKILL.md
   ```

## Never commit

- the `agy` binary (270 MB, and not ours to redistribute)
- `AGY_HOME` (contains OAuth refresh tokens)
- `ledger.jsonl` or task dirs (local state)
- `*.env` files (Outline credentials)

`.gitignore` already covers these — do not weaken it.

## Versioning notes

- `SKILL.md` is the contract agents read; `docs/CONTRACT.md` is the deeper spec. Changing the
  output format (`VERDICT|…`, `EXIT|…`) or exit codes is a **breaking** change: bump major and
  note it in the commit body.
- Measured numbers in README/CONTRACT come from real runs. If you re-measure, replace them;
  do not estimate.
