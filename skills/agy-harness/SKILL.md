---
name: agy-harness
description: "Drive the Antigravity CLI (agy) as a sub-agent harness — one-command task runner, brief templates, deterministic verifier, cost ledger, dispatch contract for delegate_task. Triggers: agy, Antigravity, agy-pilot, delegate harness, run agy, POLA 2."
version: 2.2.0
author: ATNX (Fathurrachman)
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [agy, antigravity, subagent, delegation, harness, cost]
---

# agy harness

`agy` (Antigravity CLI) as a **verifiable sub-agent worker**: one command per task, machine-checkable
result, cost logged. This skill never bundles `agy` itself — you install and log in to it yourself.

```
agy_task.sh     one task = one command (dirs, brief, run, validate, ledger, optional Outline publish)
agy_verify.sh   deterministic PASS/FAIL, zero LLM tokens
agy_usage.sh    cost + latency summary from the ledger
agy_run.sh      low-level wrapper (two transports, raw flags)
agy_to_outline.py  publish a finished task into Outline (optional)
```

Scripts live on your PATH after `./install.sh` (default `~/.local/bin`).
Templates live next to this skill (`templates/`), overridable via `AGY_SKILL_DIR`.

## Terms risk (baca sebelum menyarankan skill ini)

Driving the Antigravity CLI from a third-party agent is called out in the Antigravity ToS as a
possible breach ("using third party software, tools, or services to access the Service … is a
breach"), with possible suspension of Antigravity / Gemini CLI accounts. Use a separate disposable
Google account; never a work account; do not pool Antigravity accounts across tools; for production
use the official APIs. Full quote + risk table: `docs/TERMS.md` in the repo.

## Prerequisites

1. **agy installed** — `agy --version` works. This skill cannot install it for you.
2. **Logged in** — an isolated HOME holds the OAuth token (see "Login" below).
3. Nothing else. No Python packages, no API keys of its own.

## Quickstart

```bash
agy_task.sh --task <slug> --text "Reply with exactly: PONG" --timeout 120     # sanity
agy_task.sh --task <slug> --template analysis \
  --set "target=/path/to/file" --set "questions=..." \
  --allow-writes --timeout 420 --print-response
agy_verify.sh --task <slug> [--expect-file HASIL.md]     # re-check any time, 0 tokens
agy_usage.sh --days 7                                     # what it cost
```

## What the runner guarantees

- **directories**: per task under `$AGY_STATE_DIR` (default `~/.local/state/agy/<slug>/`)
- **brief**: written to `<state>/<slug>/brief.md`, placeholders must all be filled (else exit 2)
- **validation**: `RESULT.json` must have `status: SUCCESS` and a non-empty response
- **verification**: `agy_verify.sh` runs automatically after exit 0 → prints `VERDICT|PASS|FAIL`;
  a failing check forces exit **70** so "success" can never be a lie
- **auto-retry once** on exit 65 (tool auto-denied headless) with `--allow-writes`
- **ledger**: `$AGY_STATE_DIR/ledger.jsonl` — task, exit, status, tokens, wall, model, retry, artifacts
- **Outline publish** only on clean runs, idempotent by title (`--outline "DDMMYY · Judul"`)

## Perintah `agy_task.sh`

```
agy_task.sh --task <slug> (--text "..." | --brief <file> | --template <name> [--set k=v ...])
            [--allow-writes] [--workdir <dir>] [--timeout 300] [--model <id>]
            [--expect-json] [--print-response] [--dry-run] [--no-auto-retry]
            [--outline "<DDMMYY> · Judul Manusiawi" [--outline-parent "<judul induk>"]]
```

| Flag | Kapan dipakai |
|---|---|
| `--allow-writes` | **hampir selalu** — tanpa ini agy tidak boleh membaca file pun (exit 65) |
| `--dry-run` | lihat brief final + kelas biaya tanpa memanggil agy (0 token) |
| `--expect-json` | jawaban harus JSON valid (exit 66 kalau bukan) |
| `--model` | default `gemini-3.8-flash-high`; alternatif `claude-sonnet-4-6` (overhead lebih kecil) |
| `--outline` | terbitkan hasil ke Outline (butuh `outline-keton` env, lihat docs/CONTRACT.md) |

Templates: `analysis` (`target`, `questions`) · `code-change` (`goal`, `files`, `constraints`) ·
`review` (`target`, `focus`) · `report-json` (`request`, `schema`).

## Kapan pakai / kapan jangan

**Pakai:** kerja multi-file, >5 menit manual, second-opinion review, batch konten, butuh model lain.
**Jangan:** jawaban yang bisa selesai dengan tool biasa <5 menit, Q&A pendek, diff kecil.
Biaya minimum ~9.700 token per call; brief "baca file lalu hitung" pernah 82.000 token / 699 detik.
**Biaya ditentukan jumlah iterasi tool, bukan panjang brief.**

## Exit code → tindakan

| Exit | Arti | Tindakan |
|---|---|---|
| 0 | sukses + `VERDICT|PASS` | cek artefak sendiri (cat/stat) |
| 65 | response kosong (tool di-denied) | runner auto-retry sekali dengan `--allow-writes` |
| 66 | `--expect-json` tapi bukan JSON | perkecil permintaan / lihat `--print-response` |
| 70 | agy sukses tapi verifier menolak | baca output `agy_verify.sh`, jangan lapor sukses |
| 124 | timeout | pecah tugas; naikkan `--timeout` kalau perlu |
| 2 | argumen / placeholder salah | isi semua `--set`, cek path |

## Dispatch sub-agent (pola yang disarankan)

```
delegate_task(
  goal="<satu kalimat kerjaan yang bisa diverifikasi>",
  toolsets=["terminal", "file", "skills"],
  context="""Load skill agy-harness first: skill_view(name='agy-harness').

Run exactly ONE command, no retries, no flag edits:
agy_task.sh --task <slug> --template <analysis|code-change|review|report-json> \
  --set "k=v" --set "k=v" --allow-writes --timeout 420

If it exits non-zero, report the exit code + tail of $AGY_STATE_DIR/<slug>/out/stderr.log. Do NOT retry.
The runner already prints VERDICT|PASS|FAIL; re-run agy_verify.sh --task <slug> if you want.
Then cat the artifact to confirm real content.
Reply with ONLY this JSON, no prose:
{"status":"ok|failed","artifacts":["<abs path>"],"verification":"<EXIT line + VERDICT line + 1 line of content>","notes":"...","next":""}"""
)
```

**Tanpa artefak = belum selesai.** Parent verifikasi ulang; ringkasan sub-agent bukan bukti.
Kalau tugasnya cuma "jalankan satu perintah", jangan delegasi — panggil runner langsung.

## Permission gate (agy-auto)

`agy_run.sh` otomatis memakai hook **agy-auto** kalau terpasang di `$AGY_HOME` — jadi
`--dangerously-skip-permissions` tidak dipakai lagi. Read-only + workspace-scoped work diizinkan,
hapus rekursif di luar workspace / baca kredensial / tulis path sistem **ditolak** (fail-closed).
Matikan dengan `AGY_AUTO=0` (kembali ke perilaku lama).

Wajib untuk agy 1.5.13: `toolPermission: always-proceed` di
`$AGY_HOME/.gemini/antigravity-cli/settings.json`, overlay pemetaan `read_file`/`write_file`, dan
patch `/opt/**` → `/opt/hermes/**`. Semua langkah + hasil uji ada di `docs/AGY-AUTO.md`.

## Biaya & konkurensi (terukur)

| Skenario | Wall | Token |
|---|---|---|
| teks murni, solo | 7s | 9.700 |
| template `report-json` + baca file | 16s | 12.000 |
| template `analysis` (file kecil) | 84s | 27.500 |
| tulis 1 file, 3 paralel | 74s | 45.500 |
| baca file + hitung, 3 paralel | 214s | 82.100 |

Tidak ada 429 pada 3 paralel, tapi 2x lebih lambat dan ~2,6x lebih mahal.
**Default maksimal 2 sub-agent paralel.** 3 hanya untuk tugas sangat ringan.

## Login

Authorization-code + PKCE, redirect hosted (`antigravity.google/oauth-callback`), kode dipaste
manual, **jendela 60 detik**, tidak bisa diperpanjang; URL dan proses harus berpasangan —
jalankan di terminal interaktif, bukan lewat chat.

```bash
export AGY_HOME="${AGY_HOME:-$HOME/.agy-home}"      # isolated HOME, jangan pakai HOME utama
HOME="$AGY_HOME" agy -p "Reply with exactly: PONG" --output-format json
# buka URL → consent → tempel kode ke proses yang sama (Enter) → tunggu SUCCESS
ls "$AGY_HOME/.gemini/antigravity-cli/antigravity-oauth-token"
```

Token ada di `.gemini/antigravity-cli/antigravity-oauth-token` (**bukan** `oauth_creds.json`).
Kalau token mati, ulangi urutan yang sama; tidak perlu menghapus apa pun kecuali token rusak.

## Env vars

| Var | Default | Fungsi |
|---|---|---|
| `AGY_BIN` | `agy` dari PATH / `~/.local/bin/agy` | lokasi executable |
| `AGY_HOME` | `~/.agy-home` | HOME terisolasi yang menyimpan token |
| `AGY_STATE_DIR` | `~/.local/state/agy` | task dirs + ledger |
| `AGY_BIN_DIR` | dir script ini | lokasi `agy_run.sh` dkk (dipakai `agy_task.sh`) |
| `AGY_SKILL_DIR` | skill dir | lokasi `templates/` |
| `AGY_MODE` | `local` | `ssh` untuk menjalankan agy di host lain (`AGY_HOST`, `AGY_KEY`) |
| `OUTLINE_ENV_FILE` | `~/.config/outline-keton.env` | kredensial Outline untuk `--outline` |

Variabel di atas juga bisa dipatok permanen lewat file konfigurasi (KEY=VALUE, di-source otomatis):

```bash
~/.config/agy-harness/env      # contoh: AGY_SKILL_DIR=/path/ke/skill
```

## Pitfalls

1. `--mode plan` tidak menjawab — menulis rencana. Default `auto`.
2. `--json-schema` rusak di agy v1.5.13 (hang/ignored). Pakai template `report-json` + `--expect-json`.
3. `status: SUCCESS` + `response: ""` = tool auto-denied → exit 65 (runner auto-retry).
4. Tanpa `--allow-writes`, agy tidak boleh membaca file **sama sekali**.
5. `--sandbox` butuh user-namespace; di container sering mustahil (`unshare` diblok).
6. Kerjakan di `$AGY_STATE_DIR`, jangan `/tmp` — banyak sistem memblokir tool tulis ke sana.
7. Sub-agent punya inisiatif retry: selalu tulis "no retries" di context (pernah 4 attempt, 166k token hangus).
8. `pkill -f "<pola>"` bisa membunuh shell pemanggil — kill pakai PID.
9. Placeholder `{{...}}` yang lolos jadi bagian prompt dan hasilnya ngawur → runner menolak (exit 2).
10. Packet capability beda per akun Antigravity: warning `--mode auto is not available for this account`.
11. `--workdir` di mode `ssh` adalah path HOST, di mode `local` path lokal.

Detail kontrak penuh: `docs/CONTRACT.md` di repo.
