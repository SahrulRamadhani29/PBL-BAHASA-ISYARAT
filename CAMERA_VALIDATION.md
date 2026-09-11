# Validasi Kamera Nyata

Angka 99,30% berasal dari dataset dan tidak boleh disebut sebagai akurasi
kamera. Gunakan mode **Target uji kamera** pada halaman Kamera untuk mengukur
hasil pada HP sebenarnya.

## Protokol minimum

1. Gunakan sedikitnya 3 peserta yang tidak menjadi sumber data training.
2. Uji seluruh 24 huruf statis, masing-masing 10 kali per peserta.
3. Ulangi pada cahaya terang, cahaya redup, dan latar yang berbeda.
4. Posisikan tangan di bagian mana saja dalam frame. Pastikan telapak dan semua
   jari tidak terpotong sampai MediaPipe menampilkan status tangan terdeteksi.
5. Pilih target huruf. Deteksi langsung aktif otomatis tanpa tombol Mulai dan
   tanpa merekam video.
6. Tahan bentuk tangan sampai prediksi langsung muncul. Tekan **Reset hasil**
   sebelum pengulangan berikutnya bila diperlukan.
7. Catat persentase validasi yang ditampilkan dan pasangan huruf yang salah.

Minimum percobaan yang disarankan:

`3 peserta x 24 huruf x 10 pengulangan x 3 kondisi = 2.160 percobaan`

Laporkan akurasi kamera keseluruhan, akurasi per huruf, perangkat yang dipakai,
jarak tangan, latar, dan kondisi cahaya. Mode uji satu huruf tidak menyimpan
video. Rekaman hanya dibuat pada mode latihan bebas dan terhapus saat aplikasi
dihapus.
