# agy-harness — behaviour contract

Everything below is guaranteed by the scripts in `skills/agy-harness/bin/`. If a script violates
this document, that is a bug.

---

## 1. Files per task

Layout under `$AGY_STATE_DIR` (default `${XDG_STATE_HOME:-~/.local/state}/agy`):

```
<state>/<task>/
├── brief.md            the exact prompt sent to agy (placeholders already substituted)
├── out/
│   ├── RESULT.json     agy payload: {status, response, usage{total_tokens}, denied_actions?}
│   ├── META.json       {exit, wall_seconds, transport, model, mode, timeout, total_tokens, brief_sha256}
│   ├── stderr.log      agy stderr (contains the real reason for most failures)
│   └── workdir/        files agy produced, mirrored back (only with --allow-writes)
└── wd/                 the working directory handed to agy
<state>/ledger.jsonl    one JSON line per run (see §4)
```

Task names must be simple slugs (`[a-zA-Z0-9._-]`); `/` and `..` are rejected (exit 2) so a task
name can never escape the state dir.

## 2. Runner (`agy_task.sh`) pipeline

1. parse flags; reject unknown ones (exit 2)
2. build `<state>/<task>/brief.md` from `--text`, `--brief <file>`, or `--template <name>` + `--set`
3. **reject unfilled `{{placeholder}}`** (exit 2, lists the missing names)
4. `--dry-run` → print brief + cost class, exit 0 (**no agy call, no ledger line**)
5. run `agy_run.sh` with the flags; capture the one-line status
6. if exit 65 and `--allow-writes` was not used → **retry once** with writes (`retry=writes`)
7. validate payload: `status == SUCCESS` and non-empty `response` → otherwise exit 65
8. `--expect-json` → parse `response` as JSON, else exit 66
9. write the ledger line
10. run `agy_verify.sh`; a failing check forces exit **70**
11. `--outline` on exit 0 only → publish (idempotent by title)
12. print `EXIT|...` and `ARTIFACTS|...`; exit with the final code

Final exit codes: `0` ok · `2` usage · `65` empty response · `66` not JSON · `70` verifier rejected ·
`124` timeout · other = mirrored from agy.

## 3. Wrapper (`agy_run.sh`)

Two transports, identical output contract:

| | local (`AGY_MODE=local`, default) | ssh (`AGY_MODE=ssh`) |
|---|---|---|
| runs agy | `$AGY_BIN` with `HOME=$AGY_HOME` | `agy` on `$AGY_HOST` as that user |
| `--sandbox` | not passed (usually unavailable: `unshare` blocked) | passed with `--allow-writes` |
| `--dangerously-skip-permissions` | with `--allow-writes` | with `--allow-writes` |
| `--workdir` | local path | **remote** path, created + mirrored back via tar |
| artifacts mirror | local tar | tar over ssh |

Outputs: `OK|<transport>|<out>/RESULT.json|<tokens>|<sec>s` or `FAIL|<transport>|exit=<n>|<out>`.
Exit codes: `0` · `65` empty response · `124` timeout · `2` bad args.

## 4. Ledger schema

One JSON object per line in `$AGY_STATE_DIR/ledger.jsonl`:

```json
{"ts":"2026-11-20T10:12:59+00:00","task":"portable-test","exit":0,"status":"ok",
 "json":"na","tokens":9687,"wall":17,"model":"gemini-3.8-flash-high",
 "out":".../portable-test/out","retry":"","artifacts":".../out/RESULT.json"}
```

- `status`: `ok` | `empty` | `noparse` (payload inspection result)
- `json`: `true` | `false` | `na` (only meaningful with `--expect-json`)
- `retry`: `""` or `writes`
- Append-only. Never edited by the scripts; `agy_usage.sh` only reads.

## 5. Verifier (`agy_verify.sh`)

Checks, in order, and prints `PASS|FAIL <name> <detail>`:

| check | passes when |
|---|---|
| `task-dir` | `<state>/<task>` exists |
| `brief` | `brief.md` non-empty |
| `payload` | `RESULT.json` parses, `status == SUCCESS`, `response` non-empty |
| `meta` | `META.json` parses, `exit == 0` |
| `artifacts` | every file in `out/workdir` non-empty; empty workdir counts as read-only OK |
| `file:<x>` | only with `--expect-file x`: that file exists and is non-empty |
| `ledger` | a line for this task exists with `exit == 0` |

Final line: `VERDICT|PASS|<task>` or `VERDICT|FAIL|<task>`; exit 0 / 1. `--json` prints a machine
readable object instead.

## 6. Outline publishing (`--outline`)

- body = first `.md` in `out/workdir`, else the `response` text
- a metadata header (source path, task, model, exit, tokens, wall, ledger timestamp) is prepended
- title convention: `DDMMYY · Judul Manusiawi` (e.g. `201126 · Audit Cron Gagal Diam-diam`);
  wrong format only warns, it does not block
- publishes **only** on exit 0, and updates an existing document with the same title instead of
  duplicating it
- credentials come from `$OUTLINE_ENV_FILE` (`OUTLINE_URL`, `OUTLINE_API_KEY`, optional
  `OUTLINE_COLLECTION_DOKUMENTASI_AGENTS`) — see the `outline-keton` skill

## 7. Model default

`gemini-3.8-flash-high`. `claude-sonnet-4-6` measured roughly half the base overhead for the same
trivial prompt (5.5k vs 9.7k tokens) and is the better pick for code review. All models draw on the
same Antigravity account quota — switching models does not add quota.

## 8. Known limits

- `--json-schema` is broken in agy v1.5.13 (hangs in `auto`, ignored in `plan`) — use
  `report-json` + `--expect-json`.
- `--mode plan` produces a plan file, not an answer. Default stays `auto`.
- `--sandbox` needs user namespaces; inside most containers it fails, so the container itself is the
  isolation boundary.
- Cost scales with **tool iterations**, not brief length. A brief that makes agy read-and-compute is
  far more expensive than one that makes it write a file.
- Concurrent runs are not free: 3 parallel ≈ 2x slower, ≈2.6x tokens. Keep it to 2.
