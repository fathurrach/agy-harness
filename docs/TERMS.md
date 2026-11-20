# Terms & risk (baca ini sebelum memakai)

Ringkas: **pola pemakaian yang didukung repo ini tidak disahkan Google**, dan Terms of Service
Antigravity menyebutnya sebagai pelanggaran. Repo ini adalah alat teknis; keputusan memakainya ada
pada anda.

## Kutipan resmi

Dari <https://antigravity.google/terms> (Google Antigravity Additional Terms of Service), bagian
larangan penyalahgunaan:

> "You must not abuse, harm, interfere with, or disrupt the Service. This includes, but is not
> limited to, using the Service in connection with products not provided by us. **Using third party
> software, tools, or services to access the Service (e.g. using OpenClaw with Antigravity OAuth) is
> a breach of this Agreement.** Such actions may be grounds for suspension or termination of your
> Antigravity and/or Gemini CLI accounts."

Kutipan ini juga terkait dengan dokumen lain yang disebut sebagai satu kesatuan "Agreement":
Google Terms of Service (Universal Terms) dan Google Privacy Policy.

## Apa artinya untuk repo ini

Repo ini menjalankan **binary CLI resmi** (`agy`) — bukan implementasi ulang protokolnya — tetapi
pemicunya adalah agent pihak ketiga (Hermes, atau apa pun yang memanggil `agy_task.sh`). Kalimat
"using third party software, tools, or services to access the Service" bisa dibaca mencakup pola
itu. Kami tidak akan menyatakan pola ini aman.

Tingkat risiko per pola:

| Pola | Contoh | Penilaian |
|---|---|---|
| Membaca token Antigravity lalu memanggil endpoint/API langsung | mengumpankan akun Antigravity ke router/model-proxy lintas alat | **jelas melanggar** — inilah contoh yang disebut ToS |
| Memicu CLI resmi dari agent/skrip pihak ketiga | repo ini (`agy` dipanggil oleh Hermes) | **tidak disahkan** — abu-abu gelap, bisa dibaca sebagai pelanggaran |
| Memakai produk resmi secara interaktif | menjalankan `agy` sendiri di terminal | sesuai intended use |
| API resmi | Gemini API / Vertex AI dengan kunci API berbayar | sesuai ToS layanan masing-masing |

Sanksi yang disebut: **suspensi atau terminasi akun Antigravity dan/atau Gemini CLI**. Untuk akun
Google konsumen, efeknya bisa lebih luas daripada kehilangan akses CLI.

## Yang repo ini TIDAK lakukan

- tidak membundel atau mendistribusikan `agy`, kunci, atau token siapa pun
- tidak mem-bypass kuota, rate limit, atau pemeriksaan lisensi
- tidak menyediakan cara berbagi akun; setiap pengguna memakai akunnya sendiri
- tidak menjual atau menyediakan akses Antigravity sebagai layanan

Harness-nya sendiri netral: ia mengurus brief, verifikasi, dan pencatatan biaya untuk perintah CLI
apa pun. Risiko muncul dari **pola pemakaian**, bukan dari kode verifikasinya.

## Kalau anda ingin memakai automation ini

1. **Jangan pakai akun kerja / akun utama.** Pakai akun terpisah yang siap ditinggal kalau
   sewaktu-waktu ditangguhkan.
2. **Jangan gabungkan akun Antigravity ke banyak alat sekaligus** (router model, proxy, bot lain).
   Itu pola yang paling eksplisit disebut sebagai pelanggaran.
3. **Jangan pakai untuk layanan publik atau dijual.** Itu bukan sekadar risiko teknis.
4. **Pertimbangkan jalur resmi** untuk pekerjaan yang serius:
   - **Gemini API / Vertex AI** — berbayar, ada ToS API sendiri, aman untuk otomasi dan produksi
   - **Antigravity SDK** dan **Antigravity CLI** sesuai dokumentasi resmi mereka
5. Kalau anda butuh kepastian: baca sendiri dokumen lengkapnya dan/atau tanya di
   <https://discuss.ai.google.dev/c/antigravity/64>.

## Batasan dokumen ini

Dokumen ini bukan nasihat hukum dan bukan interpretasi resmi. Kutipan diambil apa adanya dari
halaman publik pada saat penulisan; Google dapat mengubah terms kapan saja. Yang mengikat adalah
dokumen asli di <https://antigravity.google/terms> beserta Google Terms of Service dan Privacy
Policy.
