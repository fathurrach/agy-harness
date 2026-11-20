Lakukan perubahan kode berikut di direktori kerja saat ini.

Tujuan: {{goal}}
File yang boleh disentuh: {{files}}
Batasan: {{constraints}}

Aturan:
- Baca file dulu sebelum mengubah. Jangan menulis ulang file yang tidak perlu diubah.
- Perubahan sekecil mungkin yang mencapai tujuan. Tanpa refactor tambahan, tanpa formatting massal.
- Jangan menambah dependency baru.
- Jangan menyentuh file di luar daftar di atas.
- Kalau ada tes/lint yang tersedia, jalankan dan tempel output aslinya.

Setelah selesai, tulis `LAPORAN.md` berisi:
## Yang diubah
(file → ringkasan perubahan, satu baris per file)
## Verifikasi
(perintah yang dijalankan + output kunci apa adanya, atau "TIDAK ADA TES" kalau memang tidak ada)
## Sisa/risiko

Balas satu baris: DONE LAPORAN.md
