# Use cases (semua pernah dijalankan, angka hasil ukur)

Label biaya: **murah** <10k token · **sedang** 10–25k · **berat** 25k+.
Contoh siap tempel ada di [`examples/`](../examples/).

Patokan memakai agy bukan "susah atau tidak", tapi **berapa menit kerja manual yang digantikan**.
Di bawah 5 menit → jangan pakai agy (minimum ~9,7k token per call).

---

## 1. Audit kegagalan senyap — *berat* · 99.656 token / 390s

**Kasus nyata:** dua cron mati berhari-hari tanpa ketahuan. Skrip memakai `set -e` + `2>/dev/null`,
kontainer yang dirujuk sudah dihapus, dan orkestrator tetap melaporkan `success`.

```bash
agy_task.sh --task cron-audit --brief brief-audit.md --allow-writes --timeout 540 --print-response
```

Isi brief: daftar file target + fakta yang sudah diverifikasi manusia ("container X hilang",
"file /tmp/Y tidak ada") + pertanyaan spesifik (mana yang gagal tanpa output, mana yang menelan
error, perbaikan minimal). **Fakta yang kita berikan mencegah model menebak dan menghemat iterasi.**

Hasil: temuan dengan bukti `path:baris`, termasuk satu hal yang tidak kita sebut di brief — satu
skrip menghapus file yang dibutuhkan skrip lain. Angka di atas termasuk seluruh iterasi tool-nya.

**Kapan jangan:** kalau anda cuma ingin tahu "file ini isinya apa". Baca sendiri.

---

## 2. Review kritis berkas — *jangan buka dengan pertanyaan terbuka*

Percobaan nyata dengan template `review` pada skrip 130 baris, fokus
"apakah ada kondisi di mana script melaporkan PASS padahal tidak seharusnya":

```
FAIL|local|exit=124  ·  95.185 token  ·  421s  ·  tanpa hasil
```

Wajar: pertanyaan review terbuka membuat model membaca, menyusun hipotesis, menguji, lalu mengulang.
**Pelajaran:** untuk review, batasi ruang (satu berkas, satu fokus) dan **minta keluaran pendek**
("maksimal 6 baris", "3 kondisi paling mungkin"). Kalau tetap ingin eksploratif, siapkan
`--timeout 900` dan terima biayanya.

Alternatif murah yang terbukti: lihat use case 5 (second opinion terarah, 6,5k token).

---

## 3. Data terstruktur dari file — *sedang* · 23.882 token / 132s

`--json-schema` rusak di agy v1.5.13, jadi jalurnya: template `report-json` + `--expect-json`.

```bash
agy_task.sh --task ex-json --template report-json \
  --set 'request=Baca <file> lalu keluarkan nama, versi, dan daftar file templates (urut abjad).' \
  --set 'schema={"name":"","version":"","templates":[]}' \
  --allow-writes --workdir "$(pwd)" --expect-json --timeout 300 --print-response
```

Hasil: `json=true` di baris `EXIT|` dan objek yang benar-benar bisa diparse. Kalau model menjawab
prosa, runner memberi **exit 66**. Contoh lengkap: [`examples/01-json-extract.md`](../examples/01-json-extract.md).

**Kapan jangan:** kalau data bisa diolah `jq`/`python` biasa. Ini untuk merangkum, bukan menghitung.

---

## 4. Perubahan kode kecil — *berat* · 36.268 token

```bash
agy_task.sh --task ex-code --template code-change \
  --set "goal=tambahkan validasi price negatif → ValueError" \
  --set "files=cart.py" --set "constraints=jangan ubah signature, tanpa dependency baru" \
  --allow-writes --workdir /tmp/demo --timeout 600 --print-response
```

Hasil: kode berubah benar + `LAPORAN.md` berisi daftar perubahan, output verifikasi nyata, dan sisa
risiko. Contoh lengkap: [`examples/03-code-change.md`](../examples/03-code-change.md).

**Gotcha:** dengan `--timeout 300` percobaan berakhir exit 124, **padahal artefaknya sudah lengkap**.
Timeout bukan berarti gagal — periksa `out/workdir/` sebelum membuang hasil.

---

## 5. Second opinion terarah — *murah* · 6.514 token / 15s

```bash
agy_task.sh --task ex-opinion --model claude-sonnet-4-6 \
  --text "Baca docs/CONTRACT.md bagian 'Known limits' dan jawab maksimal 6 baris: satu keputusan yang paling berisiko, alasannya, bukti nomor bagiannya." \
  --allow-writes --workdir "$(pwd)" --timeout 300 --print-response
```

Hasil nyata: menunjuk §8 (batas paralel tanpa enforcement) — kritik spesifik, bukan opini umum.
Contoh lengkap: [`examples/02-second-opinion.md`](../examples/02-second-opinion.md).

`claude-sonnet-4-6` terukur punya overhead dasar hampir separuh default (5,5k vs 9,7k token untuk
prompt trivial) → lebih murah untuk kerja berpikir.

---

## 6. Rencana refactor multi-file — *belum diukur*

```bash
agy_task.sh --task refactor-plan --template analysis \
  --set "target=src/legacy" \
  --set "questions=1) modul mana paling berisiko diubah? 2) urutan perubahan paling aman?" \
  --allow-writes --timeout 900 --print-response
```

Berguna sebagai pembanding sebelum `code-change` mengeksekusi. **Biaya belum diukur ulang di mesin
bersih**, jadi tidak dicantumkan — jangan percaya angka pinjaman.

---

## Pola yang berulang

1. **Target jelas + pertanyaan spesifik + wajib bukti.** "Cek script ini" selalu menghasilkan
   jawaban ngambang yang mahal.
2. **`--allow-writes` hampir selalu perlu** (tanpa itu exit 65), dan **`--workdir` sebaiknya diisi**
   kalau brief menyebut path relatif.
3. **Batasi panjang keluaran.** "maksimal 6 baris" menurunkan biaya nyata, bukan cuma estetika.
4. **Verifikasi sendiri:** `agy_verify.sh --task <slug>`, lalu `cat` artefaknya.
5. **Cek biaya berkala:** `agy_usage.sh --days 7`. Satu tugas rutin yang menembus ~30k token
   biasanya brief-nya terlalu luas.
