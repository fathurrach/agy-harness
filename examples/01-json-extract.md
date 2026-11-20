# 01 — Ambil data terstruktur dari file (JSON)

**Kelas biaya: sedang — terukur 23.882 token / 132 detik**

Kapan dipakai: butuh ringkasan terstruktur dari file/dokumen untuk dikonsumsi program lain
(Sheets, API, DB) dan `--json-schema` di agy sedang tidak bisa diandalkan.

```bash
R=$(pwd)     # jalankan dari root repo yang mau dibaca
agy_task.sh --task ex-json --template report-json \
  --set 'request=Baca skills/agy-harness/SKILL.md lalu keluarkan nama skill, versi, dan daftar file templates (urut abjad).' \
  --set 'schema={"name":"","version":"","templates":[]}' \
  --allow-writes --workdir "$R" --expect-json --timeout 300 --print-response
```

Hasil nyata:

```
VERDICT|PASS|ex-json
EXIT|0|status=ok|json=true|tokens=23882|wall=132s
{"name":"agy-harness","version":"2.2.0","templates":["analysis.md","code-change.md","report-json.md","review.md"]}
```

Yang perlu diperhatikan:
- `json=true` berarti jawabannya benar-benar bisa diparse. Kalau model menjawab prosa, runner
  memberi **exit 66** — bukan lolos diam-diam.
- `--workdir "$R"` penting: tanpa itu agy bekerja di workdir kosong dan path relatif tidak ketemu
  (dia akan melaporkan "file tidak ditemukan" — jujur, tapi bukan hasil).
- Biaya 23k bukan karena brief panjang, tapi karena ia membaca file + menelusuri direktori.
