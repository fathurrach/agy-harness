# Tiga jalur memanggil agy (dan kapan pakai yang mana)

`agy` bukan fitur khusus agent — dia **command biasa**. Yang dibutuhkan cuma shell. Semua jalur di
bawah memakai harness yang sama (`agy_task.sh`), jadi kontrak output, verifikasi, dan ledger tetap
identik. Bedanya cuma siapa yang menekan tombol.

| | Jalur 1 — langsung | Jalur 2 — sub-agent | Jalur 3 — cron |
|---|---|---|---|
| siapa yang kerja | agent utama | worker terpisah | script, tanpa LLM |
| biaya LLM | 1 tool call | 1 tool call + 1 LLM worker | 0 (hanya token agy) |
| cocok untuk | satu tugas, hasil ditunggu | 2–3 tugas paralel / tugas >10 menit / output besar | rutin harian-mingguan |
| hasil muncul | di pesan yang sama | sebagai pesan susulan | di chat pada jadwalnya |
| kontrol | penuh, bisa dikoreksi di tengah | agent utama hanya mengawasi | tidak ada |

## Jalur 1 — langsung (default)

Agent memanggil `agy_task.sh` lewat terminal, membaca artefak, lalu melapor. Tidak ada worker
tambahan. Ini pilihan pertama untuk hampir semua hal.

```
"pakai agy, review script riset harian"
"agy: analisis folder src/auth, cari yang gagal diam-diam"
"biaya agy minggu ini berapa?"            → agy_usage.sh, 0 token agy
```

Di Hermes, skill `agy-harness` otomatis dimuat dari kata kunci `agy`. Di agent lain, minta agent
membaca `SKILL.md` lebih dulu.

**Pakai kalau:** satu tugas, anda ingin melihat hasilnya sekarang, atau ingin bisa mengoreksi arah
di tengah jalan.

## Jalur 2 — sub-agent

Agent utama memecah pekerjaan dan mengirim worker (`delegate_task` di Hermes). Worker menjalankan
satu perintah `agy_task.sh`, memverifikasi artefak, dan mengembalikan envelope JSON. Hasil masuk
sebagai pesan susulan.

```
"suruh 2 subagent pakai agy: audit script A dan script B sekaligus"
"delegasikan ke subagent: review 3 file ini, kabari kalau selesai"
```

**Pakai kalau:** 2–3 tugas independen, tugas >10 menit dan anda tidak mau menunggu, atau output agy
sangat besar dan tidak perlu masuk ke context agent utama.

**Batas:** maksimal 2 worker paralel untuk kerja produktif (3 paralel terukur ~2x lebih lambat dan
~2,6x lebih mahal), dan worker tidak bisa bertanya balik — brief harus lengkap dalam satu pesan.

## Jalur 3 — cron tanpa LLM

Job `no_agent` yang menjalankan script; stdout dikirim apa adanya. Nol token Hermes.

```bash
# contoh isi job: audit mingguan ke Outline
agy_task.sh --task audit-weekly --template analysis \
  --set "target=$REPO" --set "questions=..." \
  --allow-writes --timeout 900 --outline "201126 · Audit Mingguan"
```

**Pakai kalau:** rutin, hasilnya bisa dinilai tanpa judgment manusia setiap kali.

## Tidak perlu sub-agent untuk

- satu file / satu pertanyaan
- pekerjaan yang bisa selesai dengan tool biasa <5 menit (agy minimum ~10k token)
- apa pun yang butuh klarifikasi di tengah jalan

Sub-agent tidak "mengaktifkan" agy — dia cuma pekerja tambahan yang menjalankan perintah yang sama.

## Contoh kalimat per jalur (chat/CLI)

| Tujuan | Kalimat |
|---|---|
| review satu file | `pakai agy, review src/auth/session.py` |
| audit diam-diam gagal | `agy: audit src/, cari kegagalan yang tidak kelihatan, wajib bukti path:baris` |
| dua file sekaligus | `suruh 2 subagent review a.py dan b.py paralel` |
| kerjaan panjang | `delegasikan audit seluruh repo ke subagent, kabari kalau selesai` |
| rutin | `bikin cron mingguan: audit repo pakai agy, simpan ke Outline` |
| cek biaya | `biaya agy 7 hari terakhir` |
| cek sehat | `agy masih hidup? jalankan preflight` |
