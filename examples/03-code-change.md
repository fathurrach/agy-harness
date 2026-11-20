# 03 — Perubahan kode kecil dengan laporan verifikasi

**Kelas biaya: berat — terukur 36.268 token; butuh timeout ≥600 detik**

Kapan dipakai: perubahan terbatas pada 1–2 file dengan batasan jelas, dan anda ingin laporan
"apa yang diubah + bagaimana diverifikasi" yang bisa dibaca manusia.

```bash
S=/tmp/demo; mkdir -p $S
printf 'def total(items):\n    return sum(i["price"] for i in items)\n' > $S/cart.py

agy_task.sh --task ex-code --template code-change \
  --set "goal=tambahkan validasi: item tanpa key price atau price negatif harus ditolak dengan ValueError" \
  --set "files=cart.py" \
  --set "constraints=jangan ubah signature fungsi, tanpa dependency baru" \
  --allow-writes --workdir $S --timeout 600 --print-response
```

Hasil nyata — `cart.py` di workdir menjadi:

```python
def total(items):
    total_price = 0
    for i in items:
        if "price" not in i or i["price"] < 0:
            raise ValueError("Item must have a non-negative price")
        total_price += i["price"]
    return total_price
```

plus `LAPORAN.md` berisi daftar perubahan, output verifikasi yang benar-benar dijalankan, dan sisa
risiko.

## Gotcha penting: timeout ≠ gagal

Dengan `--timeout 300` percobaan ini berakhir **exit 124 / 36.268 token**, tetapi artefaknya sudah
lengkap di `out/workdir/` (`cart.py` yang sudah divalidasi + `LAPORAN.md`). Artinya:

1. **Periksa `out/workdir/` sebelum membuang hasil run yang timeout** — pekerjaan bisa saja selesai,
   hanya balasan akhirnya yang lewat batas.
2. Untuk template `code-change`, pakai `--timeout 600` sebagai default.
3. Template ini memaksa model menulis laporan verifikasi; kalau tidak ada tes di repo, ia menulis
   `TIDAK ADA TES` — jangan dianggap kegagalan.
