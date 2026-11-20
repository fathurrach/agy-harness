# 02 — Second opinion atas keputusan teknis

**Kelas biaya: murah — terukur 6.514 token / 15 detik (model `claude-sonnet-4-6`)**

Kapan dipakai: butuh penilaian kritis atas dokumen/keputusan yang sudah ada, bukan menulis kode.
Cocok untuk memeriksa desain, kebijakan, atau kontrak.

```bash
R=$(pwd)
agy_task.sh --task ex-opinion --model claude-sonnet-4-6 \
  --text "Baca docs/CONTRACT.md bagian 'Known limits' dan jawab maksimal 6 baris: satu keputusan yang menurutmu paling berisiko, alasannya, dan bukti nomor bagiannya. Tanpa basa-basi." \
  --allow-writes --workdir "$R" --timeout 300 --print-response
```

Hasil nyata (dipotong): model menunjuk §8 dan menyebut tidak ada enforcement untuk batas paralel —
kritik yang spesifik, bukan opini umum. 6.514 token, 15 detik.

Yang perlu diperhatikan:
- **Batasi panjang jawaban** ("maksimal 6 baris"). Tanpa batas, model cenderung menulis esai dan
  biaya naik tanpa tambahan nilai.
- Minta **bukti nomor bagian/baris**; ini yang membedakan review dari ringkasan.
- `claude-sonnet-4-6` terukur punya overhead dasar hampir separuh model default untuk prompt
  trivial (5,5k vs 9,7k token), jadi untuk kerja berpikir ini justru lebih murah.

## Kalau lupa `--workdir`

Tanpa `--workdir`, agy bekerja di direktori kosong dan menjawab jujur:

> File `docs/CONTRACT.md` tidak ditemukan di workspace — direktori … kosong.

Itu perilaku yang benar (tidak mengarang). Perbaikannya: tambahkan `--workdir "$(pwd)"`.
