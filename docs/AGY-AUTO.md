# agy-auto permission gate (opsional, direkomendasikan)

`agy --dangerously-skip-permissions` adalah palu godam: semua tool diizinkan, tanpa rem. Alternatif
yang lebih baik: **agy-auto** (MIT, https://github.com/onkarbadve/agy-auto) — PreToolUse hook yang
memutuskan tiap tool call:

1. **hard deny** — hapus rekursif di luar workspace, `sudo`, perubahan service/firewall, baca
   kredensial (`~/.ssh`, `.env`, token OAuth agy), `curl` membawa data lokal, pipe-to-shell, tulis
   ke path sistem / `.git/` / file policy-nya sendiri
2. **fast allow** — perintah read-only & workspace-scoped yang bisa diparse (~10 ms)
3. **classifier** — endpoint OpenAI-compatible untuk kasus abu-abu (fail-closed: error/timeout = deny)
4. **escalation** — setelah beberapa penolakan yang sama, model diberi tahu agar berhenti mencoba

## Status kompatibilitas (penting)

agy-auto diverifikasi upstream untuk **agy 1.1.27 / 1.2.0**. Di repo ini dipakai dengan
**agy 1.5.13**, yang punya tiga perbedaan dan butuh penyesuaian di bawah:

| Hal | 1.1.27 / 1.2.0 | 1.5.13 (dipakai di sini) |
|---|---|---|
| Lokasi `toolPermission` | `~/.gemini/antigravity-cli/settings.json` | **sama**, tapi file belum tentu ada — dibuat manual |
| Nama tool tulis | `write_to_file` (`TargetFile`) | `write_file` (`Path`, `Content`, `Overwrite`) |
| Nama tool baca | `view_file` (`AbsolutePath`) | `read_file` (`Path`) |
| `toolPermission` salah tempat | — | kalau ditaruh di `~/.gemini/config/config.json`, **diabaikan** (tetap `request-review`) |

Kalau `toolPermission` masih `request-review`, hook tetap dipanggil tetapi **agy sendiri** yang
menolak tool ("headless mode cannot prompt for"), hasilnya `exit 65` walau audit log mencatat
`allow`. Cek dengan:

```bash
HOME=$AGY_HOME agy -p "/settings" --output-format json | grep -o '"toolPermission":"[^"]*"'
```

## Instalasi (per AGY_HOME, tidak global)

Cara tercepat — pakai fork yang sudah membawa semua penyesuaian di bawah:

```bash
git clone -b feat/agy-1.5.13-compat https://github.com/fathurrach/agy-auto.git
cd agy-auto
AGY_HOME=$HOME/.agy-home ./install-hermes.sh    # salin, set toolPermission, verifikasi, smoke test
# output yang diharapkan: hook ✓ · toolPermission ✓ · 3 smoke test ✓
```

Langkah manual (kalau tidak mau pakai installer):

```bash
# 1. plugin ke dalam AGY_HOME (agy 1.5.13 mendukung ~/.gemini/config/plugins)
git clone https://github.com/onkarbadve/agy-auto.git "$AGY_HOME/.gemini/config/plugins/agy-auto"
chmod +x "$AGY_HOME/.gemini/config/plugins/agy-auto/hook.sh"

# 2. permission mode — WAJIB, di file yang benar
printf '{\n  "toolPermission": "always-proceed"\n}\n' > "$AGY_HOME/.gemini/antigravity-cli/settings.json"

# 3. verifikasi hook terdaftar
HOME=$AGY_HOME agy -p "/hooks" --output-format json | grep -o '"name":"agy-auto"'
```

## Penyesuaian wajib untuk 1.5.13

**(a) Pemetaan nama tool** — overlay policy (dipakai lewat `AGY_AUTO_POLICY`):

```toml
[tools]
read_path_args  = { read_file = "Path", view_file = "AbsolutePath", list_dir = "DirectoryPath" }
write_path_args = { write_file = "Path", write_to_file = "TargetFile", replace_file_content = "TargetFile" }
```

Tanpa ini, `read_file`/`write_file` masuk kategori "unknown tool" → classifier → sering deny.

**(b) Workspace di bawah path sistem** (`/opt/**`, kadang `/home/**`) ditolak untuk ditulis.
Cara yang benar dan didukung upstream: `system_write_exceptions` di overlay — **jangan** mengubah
daftar `system` (overlay menggabungkan list, jadi pengecualian lebih aman dan tidak melonggarkan
path lain):

```toml
[paths]
system_write_exceptions = ["/opt/data/**"]
```

Dengan ini `/opt/data` boleh ditulis sementara `/opt/hermes` (kode Hermes) tetap ditolak.

Fork kita sudah membawa ini: lihat `policy/agy-1.5.13.toml` di
https://github.com/fathurrach/agy-auto (branch `feat/agy-1.5.13-compat`).

**(c) Classifier** — alihkan ke 9router supaya tidak butuh kunci Google AI Studio:

```toml
[classifier]
endpoint    = "http://127.0.0.1:20128/v1/chat/completions"
model       = "midas/dpe/alias/deepseek-flash"
api_key_env = "AGY_CLASSIFIER_KEY"
timeout_s   = 8
```

`agy_run.sh` mengekspor `AGY_CLASSIFIER_KEY` (dibaca dari `model.api_key` config Hermes) dan
`AGY_AUTO_POLICY` otomatis; set `AGY_AUTO=0` untuk kembali ke `--dangerously-skip-permissions`.

## Hasil uji (agy 1.5.13, mesin ini)

| Uji | Hasil |
|---|---|
| `ls -la` (workspace) | allow · fast_allow |
| `read_file` di workspace | allow |
| `read_file ~/.ssh/id_ed25519` | **deny** · hard_deny (credential) |
| `write_file` di workspace | allow |
| `write_file /opt/hermes/cli.py` | **deny** · hard_deny (system) |
| `rm -rf /` | **deny** · hard_deny |
| `rm -rf <dir di luar workspace>` saat run agy sungguhan | **deny** · direktori tetap utuh |
| `git status` (abu-abu) | allow setelah classifier 9router aktif |
| Task nyata: baca README + tulis `HASIL.md` | **exit 0**, 9.502 token, 35s — tanpa `--dangerously-skip-permissions` |

## Batasan yang tetap ada

- Hook hanya melihat **tool call**. Aktivitas agy di luar tool (membaca file untuk konteks, panggilan
  jaringan model) tidak terlihat.
- Kalau hook hilang/error, `always-proceed` berarti semua tool jalan. `hook.sh` fail-closed, dan
  `agy -p /hooks` dipakai untuk memastikan hook terdaftar.
- Unit test upstream punya 1 kegagalan di clone lokal (`s02: cat README.md` diklasifikasi karena
  README dianggap self-protection path). Bukan regresi kita, tapi jangan heran kalau menjalankannya.
- Permission ini **tidak** mengubah posisi ToS Antigravity (lihat `docs/TERMS.md`).

## Referensi

- Plugin: https://github.com/onkarbadve/agy-auto (MIT)
- Policy upstream: `policy/default.toml` di repo plugin
- Audit log: `$AGY_HOME/.gemini/config/agy-auto/audit/<conversationId>.jsonl`
