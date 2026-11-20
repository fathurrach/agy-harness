# FAQ

**Harus pakai sub-agent untuk memakai agy?**
Tidak. agy cuma command. Tiga jalur (langsung / sub-agent / cron) dijelaskan di `docs/PATHS.md`;
jalur langsung adalah default.

**Kenapa hasilnya exit 65 dan response kosong?**
agy menjalankan diri headless: tool yang butuh izin otomatis ditolak, dan ia tetap melaporkan
`status: SUCCESS`. Runner mendeteksi ini dan mengulang **sekali** dengan `--allow-writes`. Kalau
masih 65, brief-nya butuh tool yang lebih spesifik daripada yang diizinkan.

**Kenapa `--json-schema` tidak dipakai?**
Rusak di agy v1.5.13: menggantung di mode `auto`, diabaikan di mode `plan`. Gantinya template
`report-json` + `--expect-json`.

**Kenapa satu tugas bisa 10k token dan tugas lain 95k?**
Biaya mengikuti jumlah iterasi tool, bukan panjang brief. Brief yang memaksa membaca-menghitung-
memeriksa jauh lebih mahal daripada yang menyuruh menulis satu file.

**Bisakah jalan tanpa login?**
Tidak. Token OAuth per akun, disimpan di `$AGY_HOME/.gemini/antigravity-cli/antigravity-oauth-token`.
Login butuh jendela 60 detik (PKCE) — lakukan di terminal interaktif.

**Apakah aman memberi `--allow-writes`?**
Itu membuat agy bisa membaca/menulis file dan menjalankan perintah di workdir. Jalankan di
container, direktori sementara, atau git worktree — bukan di repo yang anda jaga.

**Kenapa `out/workdir` tidak berisi apa-apa?**
Tugas read-only (tanpa `--allow-writes`) memang tidak menghasilkan file; `RESULT.json` yang jadi
pegangan verifikasi.

**Boleh dipakai di cron?**
Boleh, dan disarankan untuk pekerjaan rutin — jalankan lewat script `no_agent` supaya nol token
LLM tambahan. Cek biayanya berkala dengan `agy_usage.sh --days 7`.
